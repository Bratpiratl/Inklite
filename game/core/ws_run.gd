class_name WsRun
extends RefCounted
## Ein Run im Workshop nach Batomon-Regeln. Reine Logik, Zufall über GameRng.
##
## Tag: Einkommen, Shop-Rang = Tag (plus Bonus), Angebot nach Seltenheitschancen des Rangs.
## Kaufen zum Preis der Einheit, Verkaufen nach Formel, Neu würfeln, Sperren für den nächsten Tag.
## Team (Plätze 0 bis team_slots-1) kämpft, die Bank hält Einheiten zum Verschmelzen.
## Verschmelzen: merge_counts[0] Stück Stufe 1 = Stufe 2, merge_counts[1] Stück Stufe 2 = Stufe 3.
## Kampf gegen ein gespeichertes Team desselben Tages. Niederlage kostet Leben nach Tag.
##
## Eine eigene Einheit: {"id", "level", "atk_bonus", "hp_bonus", "keywords"}.
## Shop-Fähigkeiten (on_buy, on_sell, end_of_turn, on_ally_buy, after_battlecry, start_of_turn,
## on_reroll) wirken dauerhaft. Ziele sind Einheiten im Team, nicht auf der Bank.

const TEAM := "team"
const BENCH := "bench"
const MAX_DEPTH := 20

var rs: WsRuleset
var day := 1
var gold := 0
var lives := 0
var wins := 0
var losses := 0
var draws := 0
var rank_bonus := 0
var free_rerolls := 0
var second_chance_used := false
var team: Array = []
var bench: Array = []
var offers: Array = []  # je {"id", "cost"} oder null
var locked := false
var logger: WsLogger = null
var last_battle: Dictionary = {}
## Ereignisliste des Kampfes in last_battle["events"] mitliefern (für die Anzeige).
var trace := false
## Gewählte Schwierigkeit (id aus run.difficulties), leer = alle Gegner.
var difficulty := ""

var _rng: GameRng
var _combat: WsCombat
var _depth := 0
var _offered_today: Array = []
var _bought_today: Array = []


static func create(ruleset: WsRuleset, seed_value: int, mode_override: String = "", difficulty_id: String = "") -> WsRun:
	var run := WsRun.new()
	run.rs = ruleset
	run.difficulty = difficulty_id
	run._rng = GameRng.new(seed_value)
	run._combat = WsCombat.new(ruleset, mode_override)
	run.lives = int(ruleset.section("run").get("start_lives", 10))
	run.team.resize(ruleset.team_slots())
	run.bench.resize(ruleset.bench_slots())
	run.offers.resize(int(ruleset.section("shop").get("slots", 5)))
	run._start_day()
	return run


# --- Abfragen ---

func rank() -> int:
	return rs.rank_for_day(day, rank_bonus)


func reroll_cost() -> int:
	return 0 if free_rerolls > 0 else int(rs.section("economy").get("reroll_cost", 3))


func is_victory() -> bool:
	return wins >= int(rs.section("run").get("wins_to_victory", 10))


func is_over() -> bool:
	return is_victory() or lives <= 0 or day > int(rs.section("run").get("max_days", 40))


func team_units() -> Array:
	return team.filter(func(u: Variant) -> bool: return u != null)


func owned_units() -> Array:
	return team_units() + bench.filter(func(u: Variant) -> bool: return u != null)


## Team im Kampf-Format, Platz = Index im Team.
func battle_team() -> Array:
	var result: Array = []
	for slot in team.size():
		var unit: Variant = team[slot]
		if unit != null:
			result.append({
				"id": unit["id"], "level": unit["level"], "slot": slot,
				"atk_bonus": unit["atk_bonus"], "hp_bonus": unit["hp_bonus"], "keywords": unit["keywords"].duplicate(),
			})
	return result


func slots_of(loc: String) -> Array:
	return team if loc == TEAM else bench


func free_slot(loc: String) -> int:
	var slots := slots_of(loc)
	for i in slots.size():
		if slots[i] == null:
			return i
	return -1


func can_buy(index: int) -> bool:
	if index < 0 or index >= offers.size() or offers[index] == null or is_over():
		return false
	var offer: Dictionary = offers[index]
	if gold < int(offer["cost"]):
		return false
	return free_slot(TEAM) >= 0 or free_slot(BENCH) >= 0 or _would_merge(offer["id"])


# --- Aktionen im Shop ---

## to_slot: gewünschter Teamplatz, -1 = erster freier im Team, sonst Bank.
func buy(index: int, to_slot: int = -1) -> Dictionary:
	if not can_buy(index):
		return {"ok": false}
	var offer: Dictionary = offers[index]
	var id: String = offer["id"]
	gold -= int(offer["cost"])
	offers[index] = null
	_bought_today.append(id)
	var unit := _new_unit(id, 1)
	var place := _place_new(unit, to_slot)
	if place.is_empty():
		# Platz entsteht erst durch Verschmelzen: Kopien zählen ohne Brettplatz.
		place = {"loc": "", "index": -1}
	_fire_shop(unit, place, "on_buy", {})
	if not place["loc"].is_empty():
		for other: Dictionary in _team_refs():
			if other["unit"] != unit:
				var bought_ref := other_unit_ref(unit)
				_fire_shop_listener(other, "on_ally_buy", bought_ref, {"trigger_unit": bought_ref})
	var merged := _merge_all(unit, place)
	return {"ok": true, "id": id, "merged": merged}


func sell(loc: String, index: int) -> Dictionary:
	var slots := slots_of(loc)
	if index < 0 or index >= slots.size() or slots[index] == null:
		return {"ok": false}
	var unit: Dictionary = slots[index]
	var value := rs.sell_value(unit["id"], unit["level"]) if not rs.is_token(unit["id"]) else 0
	slots[index] = null
	gold += value
	if logger != null:
		logger.sell(self, unit, value)
	_fire_shop(unit, {"loc": "", "index": -1}, "on_sell", {})
	return {"ok": true, "value": value}


func reroll() -> bool:
	if is_over():
		return false
	if free_rerolls > 0:
		free_rerolls -= 1
	elif gold >= reroll_cost():
		gold -= reroll_cost()
	else:
		return false
	_flush_shop_log()
	locked = false
	_roll_offers(false)
	for ref: Dictionary in _team_refs():
		_fire_shop(ref["unit"], ref, "on_reroll", {})
	return true


func toggle_lock() -> void:
	locked = not locked


## Tauscht zwei Plätze (Team oder Bank).
func move(from_loc: String, from_index: int, to_loc: String, to_index: int) -> bool:
	var a := slots_of(from_loc)
	var b := slots_of(to_loc)
	if from_index < 0 or from_index >= a.size() or to_index < 0 or to_index >= b.size() or a[from_index] == null:
		return false
	var tmp: Variant = b[to_index]
	b[to_index] = a[from_index]
	a[from_index] = tmp
	return true


## Rundenende, Kampf, Ergebnis, nächster Tag. ghost: {"id", "team"} oder leer (dann zufällig aus dem Regelsatz).
func fight(ghost: Dictionary = {}) -> Dictionary:
	if is_over():
		return {}
	_flush_shop_log()
	var repeats := 2 if _team_has_passive("end_of_turn_twice") else 1
	for ref: Dictionary in _team_refs():
		for r in repeats:
			_fire_shop(ref["unit"], ref, "end_of_turn", {})
	if ghost.is_empty():
		var pool := rs.ghost_pool(day, wins, difficulty)
		ghost = _rng.pick(pool) if not pool.is_empty() else {"id": "leer", "team": []}
	var seed_value := _rng.next_int(2147483647)
	var mine := battle_team()
	_combat.trace = trace
	var result := _combat.simulate(mine, ghost.get("team", []), seed_value)
	_apply_permanent(result["permanent"][0])

	var outcome := "draw"
	if result["winner"] == 0:
		outcome = "win"
	elif result["winner"] == 1:
		outcome = "loss"
	elif rs.section("run").get("draw_result", "draw") in ["win", "loss"]:
		outcome = rs.section("run")["draw_result"]
	var lost_lives := 0
	match outcome:
		"win":
			wins += 1
		"loss":
			losses += 1
			lost_lives = rs.life_loss_for_day(day)
			lives -= lost_lives
			if lives <= 0 and rs.section("run").get("second_chance", false) and not second_chance_used:
				second_chance_used = true
				lives = 1
		_:
			draws += 1
	last_battle = {
		"day": day, "seed": seed_value, "ghost_id": ghost.get("id", ""), "result": outcome,
		"attacks": result["attacks"], "ticks": result["ticks"], "winner": result["winner"],
		"ghost_strength": ghost.get("strength", -1), "difficulty": difficulty,
		"survivors": result["survivors"], "lost_lives": lost_lives, "team": mine,
	}
	if trace:
		last_battle["events"] = result["events"]
	if logger != null:
		logger.battle(self, last_battle)
	day += 1
	if is_over():
		if logger != null:
			logger.run_end(self)
	else:
		_start_day()
	return last_battle


# --- Tagesablauf und Angebot ---

func _start_day() -> void:
	var eco := rs.section("economy")
	var income := rs.income_for_day(day)
	gold = gold + income if eco.get("gold_carries_over", true) else income
	free_rerolls += int(eco.get("free_rerolls_per_day", 0))
	_roll_offers(locked)
	locked = false
	for ref: Dictionary in _team_refs():
		_fire_shop(ref["unit"], ref, "start_of_turn", {})


## keep_existing: gesperrtes Angebot behalten und nur leere Plätze füllen.
func _roll_offers(keep_existing: bool) -> void:
	var weights := rs.rarity_weights(rank())
	for i in offers.size():
		if keep_existing and offers[i] != null:
			continue
		var id := _roll_unit(weights)
		offers[i] = {"id": id, "cost": rs.cost(id)} if id != "" else null
	_offered_today = []
	for offer: Variant in offers:
		if offer != null:
			_offered_today.append(offer["id"])
	_bought_today = []


func _roll_unit(weights: Array) -> String:
	var total := 0
	for w: int in weights:
		total += w
	if total <= 0:
		return ""
	var roll := _rng.next_int(total)
	var rarity := 0
	for r in weights.size():
		roll -= int(weights[r])
		if roll < 0:
			rarity = r
			break
	# Fehlt in der Seltenheit eine gültige Einheit, eine Stufe tiefer würfeln.
	for r in range(rarity, -1, -1):
		var ids := _eligible(r)
		if not ids.is_empty():
			return _rng.pick(ids)
	return ""


func _eligible(rarity: int) -> Array:
	var ids := rs.ids_of_rarity(rarity)
	if not rs.section("shop").get("exclude_owned_max_level", true):
		return ids
	var max_level := int(rs.section("board").get("max_level", 3))
	var maxed := {}
	for unit: Dictionary in owned_units():
		if int(unit["level"]) >= max_level:
			maxed[unit["id"]] = true
	return ids.filter(func(id: String) -> bool: return not maxed.has(id))


func _flush_shop_log() -> void:
	if logger != null and not _offered_today.is_empty():
		logger.shop(self, _offered_today, _bought_today)
	_offered_today = []
	_bought_today = []


# --- Platzieren und Verschmelzen ---

func _new_unit(id: String, level: int) -> Dictionary:
	return {"id": id, "level": level, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}


func _place_new(unit: Dictionary, to_slot: int) -> Dictionary:
	if to_slot >= 0 and to_slot < team.size() and team[to_slot] == null:
		team[to_slot] = unit
		return {"loc": TEAM, "index": to_slot, "unit": unit}
	for loc in [TEAM, BENCH]:
		var i := free_slot(loc)
		if i >= 0:
			slots_of(loc)[i] = unit
			return {"loc": loc, "index": i, "unit": unit}
	return {}


func _would_merge(id: String) -> bool:
	var counts: Array = rs.section("board").get("merge_counts", [3, 2])
	var copies := owned_units().filter(func(u: Dictionary) -> bool: return u["id"] == id and int(u["level"]) == 1).size()
	return not counts.is_empty() and copies + 1 >= int(counts[0])


## Verschmilzt, solange genug gleiche Einheiten derselben Stufe da sind. Liefert die erreichte Stufe oder 0.
func _merge_all(new_unit: Dictionary, place: Dictionary) -> int:
	var counts: Array = rs.section("board").get("merge_counts", [3, 2])
	var max_level := int(rs.section("board").get("max_level", 3))
	var reached := 0
	var current := new_unit
	var homeless: bool = place["loc"].is_empty()
	while int(current["level"]) < max_level and int(current["level"]) - 1 < counts.size():
		var level := int(current["level"])
		var need := int(counts[level - 1])
		var refs := _refs_of(current["id"], level)
		var total := refs.size() + (1 if homeless else 0)
		if total < need:
			break
		var used: Array = refs.slice(0, need - (1 if homeless else 0))
		var merged := _new_unit(current["id"], level + 1)
		var ingredients: Array = used.map(func(r: Dictionary) -> Dictionary: return r["unit"])
		if homeless:
			ingredients.append(current)
		_combine_bonuses(merged, ingredients)
		# Ergebnis landet auf dem ersten Teamplatz der Zutaten, sonst auf dem ersten Bankplatz.
		var target: Dictionary = used[0]
		for r: Dictionary in used:
			if r["loc"] == TEAM:
				target = r
				break
		for r: Dictionary in used:
			slots_of(r["loc"])[r["index"]] = null
		slots_of(target["loc"])[target["index"]] = merged
		homeless = false
		current = merged
		reached = level + 1
	if homeless:
		# Kein Platz und kein Verschmelzen: Kauf zurückgeben.
		gold += rs.cost(new_unit["id"])
	return reached


func _combine_bonuses(merged: Dictionary, ingredients: Array) -> void:
	var mode: String = rs.section("board").get("merge_bonus", "max")
	for unit: Dictionary in ingredients:
		for stat in ["atk_bonus", "hp_bonus"]:
			if mode == "sum":
				merged[stat] += int(unit[stat])
			else:
				merged[stat] = maxi(int(merged[stat]), int(unit[stat]))
		for keyword: String in unit["keywords"]:
			if not merged["keywords"].has(keyword):
				merged["keywords"].append(keyword)


func _refs_of(id: String, level: int) -> Array:
	var result: Array = []
	for loc in [TEAM, BENCH]:
		var slots := slots_of(loc)
		for i in slots.size():
			var unit: Variant = slots[i]
			if unit != null and unit["id"] == id and int(unit["level"]) == level:
				result.append({"loc": loc, "index": i, "unit": unit})
	return result


func _apply_permanent(perm: Dictionary) -> void:
	for slot: int in perm:
		if slot < 0 or slot >= team.size() or team[slot] == null:
			continue
		var unit: Dictionary = team[slot]
		unit["atk_bonus"] += int(perm[slot]["atk"])
		unit["hp_bonus"] += int(perm[slot]["hp"])
		for keyword: String in perm[slot]["keywords"]:
			if not unit["keywords"].has(keyword):
				unit["keywords"].append(keyword)


# --- Shop-Fähigkeiten ---

func _team_refs() -> Array:
	var result: Array = []
	for i in team.size():
		if team[i] != null:
			result.append({"loc": TEAM, "index": i, "unit": team[i]})
	return result


func other_unit_ref(unit: Dictionary) -> Dictionary:
	for loc in [TEAM, BENCH]:
		var slots := slots_of(loc)
		for i in slots.size():
			if slots[i] == unit:
				return {"loc": loc, "index": i, "unit": unit}
	return {"loc": "", "index": -1, "unit": unit}


func _abilities(unit: Dictionary) -> Array:
	return rs.level_stats(unit["id"], int(unit["level"])).get("abilities", [])


func _colors(unit: Dictionary) -> Array:
	return rs.get_def(unit["id"]).get("colors", [])


func _fire_shop(unit: Dictionary, ref: Dictionary, trigger: String, ctx: Dictionary) -> void:
	var fired := false
	for ability: Dictionary in _abilities(unit):
		if ability.get("trigger", "") != trigger:
			continue
		var repeats := 1
		if trigger == "on_buy" and _team_has_passive("battlecry_twice"):
			repeats = 2
		for r in repeats:
			_apply_shop(unit, ref, ability, ctx)
		fired = true
	if fired and trigger == "on_buy":
		for other: Dictionary in _team_refs():
			if other["unit"] != unit:
				var source_ref := other_unit_ref(unit)
				_fire_shop_listener(other, "after_battlecry", source_ref, {"trigger_unit": source_ref})


func _fire_shop_listener(listener: Dictionary, trigger: String, trigger_unit: Dictionary, ctx: Dictionary) -> void:
	for ability: Dictionary in _abilities(listener["unit"]):
		if ability.get("trigger", "") != trigger:
			continue
		if not _matches(ability.get("when"), trigger_unit):
			continue
		_apply_shop(listener["unit"], listener, ability, ctx)


func _apply_shop(unit: Dictionary, ref: Dictionary, ability: Dictionary, ctx: Dictionary) -> void:
	if _depth >= MAX_DEPTH:
		return
	_depth += 1
	var effect: String = ability.get("effect", "")
	var times := 1 if effect == "summon" else maxi(int(ability.get("times", 1)), 1)
	for t in times:
		match effect:
			"gold":
				gold += int(ability.get("value", 0))
			"free_reroll":
				free_rerolls += int(ability.get("value", 0))
			"summon":
				var token: String = ability.get("token", "")
				for n in maxi(int(ability.get("times", 1)), 1):
					if token != "":
						_place_new(_new_unit(token, int(unit["level"])), -1)
			_:
				for target: Dictionary in _shop_targets(unit, ref, ability, ctx):
					_apply_shop_to(unit, ability, target)
	_depth -= 1


func _apply_shop_to(source: Dictionary, ability: Dictionary, target: Dictionary) -> void:
	var t: Dictionary = target["unit"]
	match ability.get("effect", ""):
		"buff":
			var add_atk := int(ability.get("atk", 0))
			if ability.get("value_from", "") == "atk":
				add_atk += _unit_atk(source)
			t["atk_bonus"] += add_atk
			t["hp_bonus"] += int(ability.get("hp", 0))
			var keyword: String = ability.get("keyword", "")
			if keyword != "" and not t["keywords"].has(keyword):
				t["keywords"].append(keyword)
		"give_keyword":
			var keyword: String = ability.get("keyword", "")
			if keyword == "random":
				var base: Array = rs.get_def(t["id"]).get("keywords", [])
				var missing: Array = WsRuleset.RANDOM_KEYWORDS.filter(func(k: String) -> bool:
					return not base.has(k) and not t["keywords"].has(k))
				keyword = _rng.pick(missing) if not missing.is_empty() else ""
			if keyword != "" and not t["keywords"].has(keyword):
				t["keywords"].append(keyword)
		"remove_keyword":
			for keyword: String in ability.get("keywords", []):
				t["keywords"].erase(keyword)
		"trigger_ability":
			var trigger: String = ability.get("ability_trigger", "")
			for other: Dictionary in _abilities(t):
				if other.get("trigger", "") == trigger:
					_apply_shop(t, target, other, {})
		"damage", "destroy", "attack_now":
			pass  # nur im Kampf
		_:
			push_error("Unbekannter Effekt im Shop: %s" % ability.get("effect", ""))


func _shop_targets(unit: Dictionary, ref: Dictionary, ability: Dictionary, ctx: Dictionary) -> Array:
	var rule: String = ability.get("target", "self")
	var allies := _team_refs()
	var pool: Array = []
	match rule:
		"self":
			if not ref.get("loc", "").is_empty() and slots_of(ref["loc"])[ref["index"]] == unit:
				pool = [ref]
		"adjacent":
			if ref.get("loc", "") == TEAM:
				for n in rs.slot_neighbors(ref["index"]):
					if team[n] != null:
						pool.append({"loc": TEAM, "index": n, "unit": team[n]})
		"allies_all", "ally_random", "ally_leftmost":
			pool = allies
		"allies_other", "ally_random_other":
			pool = allies.filter(func(r: Dictionary) -> bool: return r["unit"] != unit)
		"trigger_unit":
			var other: Variant = ctx.get("trigger_unit")
			if other is Dictionary and not other.get("loc", "").is_empty():
				pool = [other]
		_:
			pass  # Gegner-Ziele gibt es im Shop nicht
	pool = pool.filter(func(r: Dictionary) -> bool: return _matches(ability.get("only"), r))
	if rule == "ally_leftmost":
		return pool.slice(0, 1)
	if rule in ["ally_random", "ally_random_other"]:
		var picks := maxi(int(ability.get("picks", 1)), 1)
		if pool.size() > picks:
			pool = pool.duplicate()
			_rng.shuffle(pool)
			pool = pool.slice(0, picks)
	return pool


func _matches(filter: Variant, ref: Dictionary) -> bool:
	if not (filter is Dictionary):
		return true
	var unit: Dictionary = ref["unit"]
	if filter.has("color") and not _colors(unit).has(filter["color"]):
		return false
	if filter.has("keyword"):
		var base: Array = rs.get_def(unit["id"]).get("keywords", [])
		if not base.has(filter["keyword"]) and not unit["keywords"].has(filter["keyword"]):
			return false
	if filter.has("has_trigger"):
		var found := false
		for ability: Dictionary in _abilities(unit):
			if ability.get("trigger", "") == filter["has_trigger"]:
				found = true
		if not found:
			return false
	return true


func _unit_atk(unit: Dictionary) -> int:
	return int(rs.level_stats(unit["id"], int(unit["level"])).get("atk", 0)) + int(unit["atk_bonus"])


func _team_has_passive(passive: String) -> bool:
	for unit: Dictionary in team_units():
		if rs.get_def(unit["id"]).get("passives", []).has(passive):
			return true
	return false
