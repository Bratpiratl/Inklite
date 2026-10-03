class_name WsBots
extends RefCounted
## Bots für Workshop-Runs (tools/ws_simulate.gd). Nur für Werkzeuge, nicht im Spiel.
##   random:  kauft zufällig, würfelt manchmal neu, verkauft bei vollem Brett manchmal, stellt nicht um. Untergrenze.
##   greedy:  kauft zuerst, was verschmilzt, sonst das Teuerste; verkauft Schwaches für Besseres.
##   synergy: wie greedy, bevorzugt aber eine Farbe und verkauft fremde Farben zuerst.
## Verhaltenswerte stehen im Regelsatz unter "bots".

const NAMES: Array[String] = ["random", "greedy", "synergy"]
const MERGE_BONUS_FULL := 120
const MERGE_BONUS_PAIR := 35
const FOCUS_BONUS := 30

var kind: String
var focus_color := ""

var _rs: WsRuleset
var _rng: GameRng
var _rules: Dictionary


func _init(bot_kind: String, ruleset: WsRuleset, rng: GameRng) -> void:
	kind = bot_kind
	_rs = ruleset
	_rng = rng
	_rules = ruleset.section("bots")
	if kind == "synergy":
		var colors: Array = ruleset.rules.get("colors", []).map(func(c: Dictionary) -> String: return c["id"])
		focus_color = _rng.pick(colors) if not colors.is_empty() else ""


func play_shop(run: WsRun) -> void:
	for i in int(_rules.get("max_actions_per_day", 60)):
		if not _act(run):
			break
	_fill_team(run)
	if kind != "random":
		_arrange(run)


func _act(run: WsRun) -> bool:
	var buyable: Array[int] = []
	for i in run.offers.size():
		if run.can_buy(i):
			buyable.append(i)
	if kind == "random":
		if not buyable.is_empty():
			return run.buy(_rng.pick(buyable))["ok"]
		if run.free_slot(WsRun.TEAM) < 0 and run.free_slot(WsRun.BENCH) < 0 and _rng.next_int(100) < 30:
			return run.sell(WsRun.BENCH, _rng.next_int(run.bench.size()))["ok"]
		if run.gold >= run.reroll_cost() and _rng.next_int(100) < int(_rules.get("random_reroll_percent", 40)):
			return run.reroll()
		return false

	var best := -1
	var best_score := -1
	for i in buyable:
		var score := _offer_score(run, run.offers[i]["id"])
		if score > best_score:
			best_score = score
			best = i
	if best >= 0:
		return run.buy(best)["ok"]
	if _sell_for_upgrade(run):
		return true
	if run.gold >= maxi(run.reroll_cost(), int(_rules.get("greedy_reroll_min_gold", 13))) or (run.free_rerolls > 0):
		return run.reroll()
	return false


func _offer_score(run: WsRun, id: String) -> int:
	var score := _rs.cost(id)
	var copies := 0
	for unit: Dictionary in run.owned_units():
		if unit["id"] == id and int(unit["level"]) == 1:
			copies += 1
	var counts: Array = _rs.section("board").get("merge_counts", [3, 2])
	var need := int(counts[0]) if not counts.is_empty() else 3
	if copies >= need - 1:
		score += MERGE_BONUS_FULL
	elif copies > 0:
		score += MERGE_BONUS_PAIR
	if kind == "synergy" and _rs.get_def(id).get("colors", []).has(focus_color):
		score += FOCUS_BONUS
	return score


## Stärke einer eigenen Einheit für Tausch und Aufstellung.
func power(unit: Dictionary) -> int:
	var mult: Array = _rs.section("economy").get("sell_level_multiplier", [1, 3, 6])
	var level := int(unit["level"])
	var value := _rs.cost(unit["id"]) * int(mult[clampi(level - 1, 0, mult.size() - 1)])
	if _rs.is_token(unit["id"]):
		value = 4 * level
	value += 2 * (int(unit["atk_bonus"]) + int(unit["hp_bonus"]))
	if kind == "synergy" and _rs.get_def(unit["id"]).get("colors", []).has(focus_color):
		value += FOCUS_BONUS
	return value


## Verkauft die schwächste Einheit ohne Verschmelz-Partner, wenn dafür etwas klar Besseres kaufbar wird.
func _sell_for_upgrade(run: WsRun) -> bool:
	if run.free_slot(WsRun.TEAM) >= 0 or run.free_slot(WsRun.BENCH) >= 0:
		return false
	var weakest := {}
	var weakest_power := 1 << 30
	for loc in [WsRun.BENCH, WsRun.TEAM]:
		var slots := run.slots_of(loc)
		for i in slots.size():
			var unit: Variant = slots[i]
			if unit == null or _has_partner(run, unit):
				continue
			var p := power(unit)
			if p < weakest_power:
				weakest_power = p
				weakest = {"loc": loc, "index": i, "unit": unit}
	if weakest.is_empty():
		return false
	var value := _rs.sell_value(weakest["unit"]["id"], int(weakest["unit"]["level"]))
	for offer: Variant in run.offers:
		if offer == null:
			continue
		var score := _offer_score(run, offer["id"])
		if score * 2 > weakest_power * 3 and run.gold + value >= int(offer["cost"]):
			return run.sell(weakest["loc"], weakest["index"])["ok"]
	return false


func _has_partner(run: WsRun, unit: Dictionary) -> bool:
	if int(unit["level"]) >= int(_rs.section("board").get("max_level", 3)):
		return false
	var n := 0
	for other: Dictionary in run.owned_units():
		if other["id"] == unit["id"] and int(other["level"]) == int(unit["level"]):
			n += 1
	return n >= 2


## Füllt leere Teamplätze von der Bank.
func _fill_team(run: WsRun) -> void:
	for b in run.bench.size():
		if run.bench[b] == null:
			continue
		var free := run.free_slot(WsRun.TEAM)
		if free < 0:
			return
		run.move(WsRun.BENCH, b, WsRun.TEAM, free)


## Stärkste Einheiten ins Team, Spott und viel HP nach vorne bzw. links.
func _arrange(run: WsRun) -> void:
	var all: Array = run.owned_units()
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return power(a) > power(b))
	var team_size := run.team.size()
	var chosen: Array = all.slice(0, team_size)
	var rest: Array = all.slice(team_size)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _front_score(a) > _front_score(b))
	for i in team_size:
		run.team[i] = chosen[i] if i < chosen.size() else null
	for i in run.bench.size():
		run.bench[i] = rest[i] if i < rest.size() else null


func _front_score(unit: Dictionary) -> int:
	var stats := _rs.level_stats(unit["id"], int(unit["level"]))
	var keywords: Array = stats.get("keywords", []) + unit["keywords"]
	var score := int(stats.get("hp", 0)) + int(unit["hp_bonus"])
	if keywords.has("taunt"):
		score += 1000
	if keywords.has("divine_shield"):
		score += 20
	return score
