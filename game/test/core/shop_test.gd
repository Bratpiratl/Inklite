extends GdUnitTestSuite

const H := preload("res://test/core/combat_test_helper.gd")


func _db() -> MonsterDb:
	return MonsterDb.from_file()


func _rules() -> Dictionary:
	return GameData.load_balance()["run"]


func test_round_one_offers_only_rarity_one() -> void:
	var db := _db()
	for s in 50:
		for id in Shop.roll(db, _rules(), 1, GameRng.new(s)):
			assert_int(int(db.get_def(id)["rarity"])).is_equal(1)


func test_offer_count_follows_round() -> void:
	var rules := _rules()
	assert_int(Shop.roll(_db(), rules, 1, GameRng.new(1)).size()).is_equal(int(rules["shop_size_by_round"][0]))
	# Nach dem Ende der Liste gilt der letzte Eintrag weiter.
	assert_int(Shop.roll(_db(), rules, 99, GameRng.new(1)).size()).is_equal(int(rules["shop_size_by_round"][-1]))


func test_rarity_weights_are_respected() -> void:
	var rules := {"shop_size_by_round": [1], "rarity_weights_by_round": [[0, 0, 100]]}
	var db := _db()
	for s in 20:
		var id: String = Shop.roll(db, rules, 1, GameRng.new(s))[0]
		assert_int(int(db.get_def(id)["rarity"])).is_equal(3)


func test_same_seed_same_offers() -> void:
	assert_array(Shop.roll(_db(), _rules(), 5, GameRng.new(77))).is_equal(Shop.roll(_db(), _rules(), 5, GameRng.new(77)))


func test_gold_and_sell_value_from_data() -> void:
	var rules := _rules()
	assert_int(Shop.gold_for_round(rules, 1)).is_equal(int(rules["gold_per_round"][0]))
	assert_int(Shop.gold_for_round(rules, 50)).is_equal(int(rules["gold_per_round"][-1]))
	assert_int(Shop.sell_value(rules, 2)).is_equal(int(rules["sell_value_by_level"][1]))
