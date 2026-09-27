class_name Shop
extends RefCounted
## Shop-Regeln: Angebote würfeln, Preise, Verkaufswert. Alle Zahlen aus balance.json ("run").
## Listen "..._by_round" gelten ab Runde 1; ist die Liste kürzer, gilt ihr letzter Eintrag weiter.


static func by_round(list: Array, round_number: int) -> Variant:
	if list.is_empty():
		return null
	return list[clampi(round_number - 1, 0, list.size() - 1)]


static func price(db: MonsterDb, id: String) -> int:
	return int(db.get_def(id).get("cost", 0))


static func sell_value(rules: Dictionary, level: int) -> int:
	return int(by_round(rules.get("sell_value_by_level", []), level))


static func gold_for_round(rules: Dictionary, round_number: int) -> int:
	return int(by_round(rules.get("gold_per_round", []), round_number))


static func shop_size(rules: Dictionary, round_number: int) -> int:
	return int(by_round(rules.get("shop_size_by_round", []), round_number))


## Würfelt die Angebote einer Runde: erst Seltenheit nach Gewicht, dann Monster dieser Seltenheit.
static func roll(db: MonsterDb, rules: Dictionary, round_number: int, rng: GameRng) -> Array[String]:
	var weights: Array = by_round(rules.get("rarity_weights_by_round", []), round_number)
	var by_rarity := {}
	for id in db.ids():
		var rarity := int(db.get_def(id)["rarity"])
		if not by_rarity.has(rarity):
			by_rarity[rarity] = []
		by_rarity[rarity].append(id)
	var offers: Array[String] = []
	for i in shop_size(rules, round_number):
		var rarity := _weighted_rarity(weights, by_rarity, rng)
		offers.append(rng.pick(by_rarity[rarity]))
	return offers


## weights[0] gehört zu Seltenheit 1 usw. Seltenheiten ohne Monster fallen heraus.
static func _weighted_rarity(weights: Array, by_rarity: Dictionary, rng: GameRng) -> int:
	var total := 0
	for i in weights.size():
		if by_rarity.has(i + 1):
			total += int(weights[i])
	var roll_value := rng.next_int(maxi(total, 1))
	for i in weights.size():
		if not by_rarity.has(i + 1):
			continue
		roll_value -= int(weights[i])
		if roll_value < 0:
			return i + 1
	return by_rarity.keys().min()
