class_name Bots
extends RefCounted
## Bot-Strategien für komplette Runs in tools/simulate.gd. Nur für Werkzeuge, nicht im Spiel.
##   random:  kauft zufällig, würfelt manchmal neu, verkauft nie, stellt nicht um. Untergrenze.
##   greedy:  kauft zuerst, was sofort verschmilzt, sonst das Teuerste; tauscht bei vollem Raster
##            billige gegen teure Monster; stellt die HP-stärksten nach vorne.
##   synergy: wählt einen Typ und den passenden Trainer, kauft bevorzugt diesen Typ und
##            tauscht fremde Typen aus; stellt die HP-stärksten nach vorne.
## Verhaltenswerte stehen in balance.json unter "bots".

const NAMES: Array[String] = ["random", "greedy", "synergy"]

var kind: String
var focus_type := ""  # nur synergy

var _db: MonsterDb
var _items: ItemDb
var _rng: GameRng
var _rules: Dictionary


func _init(bot_kind: String, db: MonsterDb, items: ItemDb, rng: GameRng, bot_rules: Dictionary) -> void:
	kind = bot_kind
	_db = db
	_items = items
	_rng = rng
	_rules = bot_rules


func choose_trainer() -> String:
	var trainers := _items.trainer_ids()
	if kind == "synergy":
		var types := {}
		for id in _db.ids():
			types[_db.get_def(id)["type"]] = true
		focus_type = _rng.pick(types.keys())
		for id in trainers:
			if _item_type(_items.trainer(id)) == focus_type:
				return id
	return _rng.pick(trainers)


func choose_trinket(run: RunState) -> String:
	if kind == "synergy":
		for id: String in run.pending_trinkets:
			if _item_type(_items.trinket(id)) == focus_type:
				return id
	return _rng.pick(run.pending_trinkets)


## Spielt eine komplette Shop-Phase. Danach kann gekämpft werden.
func play_shop(run: RunState) -> void:
	if not run.pending_trinkets.is_empty():
		run.choose_trinket(choose_trinket(run))
	for i in int(_rules.get("max_actions_per_round", 50)):
		if not _act(run):
			break
	if kind != "random":
		_arrange(run)


## Eine Aktion. false, wenn der Bot fertig ist.
func _act(run: RunState) -> bool:
	var buyable: Array[int] = []
	for i in run.offers.size():
		if run.can_buy(i):
			buyable.append(i)
	match kind:
		"random":
			if not buyable.is_empty():
				return run.buy(_rng.pick(buyable))["ok"]
			if run.gold >= run.reroll_cost() and _rng.next_int(100) < int(_rules.get("random_reroll_percent", 0)):
				return run.reroll()
			return false
		_:
			var choice := _best_offer(run, buyable)
			if choice >= 0:
				return run.buy(choice)["ok"]
			if _swap(run):
				return true
			var min_gold := int(_rules.get("%s_reroll_min_gold" % kind, 1))
			if run.gold >= maxi(run.reroll_cost(), min_gold):
				return run.reroll()
			return false


## greedy: Verschmelzen vor Preis. synergy: eigener Typ zuerst, fremde nur bei freiem Platz.
func _best_offer(run: RunState, buyable: Array[int]) -> int:
	var best := -1
	var best_score := -1
	for i in buyable:
		var id: String = run.offers[i]
		var score := run.price(i)
		if _copies(run, id) >= 2:
			score += 100
		if kind == "synergy":
			if _db.get_def(id)["type"] == focus_type:
				score += 50
			elif run.unit_count() >= CombatSim.SLOTS - 2:
				continue
		if score > best_score:
			best_score = score
			best = i
	return best


## Raster voll: schwächstes Monster verkaufen, wenn dafür ein besseres Angebot bezahlbar wird.
func _swap(run: RunState) -> bool:
	if run.unit_count() < CombatSim.SLOTS:
		return false
	var weakest := -1
	var weakest_value := 1 << 30
	for slot in CombatSim.SLOTS:
		var unit: Variant = run.board[slot]
		if unit == null or unit["level"] > 1:
			continue
		var value := _unit_value(unit)
		if value < weakest_value:
			weakest_value = value
			weakest = slot
	if weakest < 0:
		return false
	for i in run.offers.size():
		var id: String = run.offers[i]
		if id == "" or _unit_value({"id": id, "level": 1}) <= weakest_value:
			continue
		if run.gold + run.sell_value(weakest) >= run.price(i):
			run.sell(weakest)
			return run.buy(i)["ok"]
	return false


func _unit_value(unit: Dictionary) -> int:
	var value := int(_db.get_def(unit["id"])["cost"]) * 10
	if kind == "synergy" and _db.get_def(unit["id"])["type"] == focus_type:
		value += 100
	return value


## HP-stärkste nach vorne (Slot 0 ist vorne links).
func _arrange(run: RunState) -> void:
	var units: Array = run.board.filter(func(u: Variant) -> bool: return u != null)
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _hp(a) > _hp(b))
	for target in units.size():
		var current := run.board.find(units[target], target)
		if current != target:
			run.move(current, target)


func _hp(unit: Dictionary) -> int:
	return int(_db.level_stats(unit["id"], unit["level"])["hp"]) + int(unit.get("hp_bonus", 0))


func _copies(run: RunState, id: String) -> int:
	var count := 0
	for unit: Variant in run.board:
		if unit != null and unit["id"] == id and unit["level"] == 1:
			count += 1
	return count


static func _item_type(def: Dictionary) -> String:
	var ability: Dictionary = def.get("ability", {})
	for key in ["when", "only"]:
		if ability.get(key) is Dictionary and ability[key].has("type"):
			return ability[key]["type"]
	return ""
