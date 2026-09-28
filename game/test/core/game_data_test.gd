extends GdUnitTestSuite
## Prüft balance.json und ghost_teams.json auf Vollständigkeit und gültige Verweise.


func test_balance_has_run_rules() -> void:
	var run: Dictionary = GameData.load_balance()["run"]
	for key in ["start_lives", "wins_to_victory", "gold_per_round", "reroll_cost", "sell_value_by_level",
			"merge_count", "shop_size_by_round", "rarity_weights_by_round", "ghost_round_lag", "ghost_match_pool",
			"trinket_every_wins", "trinket_choices"]:
		assert_bool(run.has(key)).override_failure_message("balance.json/run fehlt: " + key).is_true()
	for weights: Array in run["rarity_weights_by_round"]:
		assert_int(weights.size()).is_equal(3)


func test_ghost_teams_are_valid() -> void:
	var db := MonsterDb.from_file()
	var data: Dictionary = GameData.load_json("res://data/ghost_teams.json")
	var teams: Array = data["teams"]
	assert_array(teams).is_not_empty()
	var rounds := {}
	for ghost: Dictionary in teams:
		rounds[int(ghost["round"])] = true
		var slots := {}
		for unit: Dictionary in ghost["team"]:
			assert_bool(db.has(unit["id"])).override_failure_message("Unbekanntes Monster in %s" % ghost["id"]).is_true()
			assert_int(int(unit["level"])).is_between(1, 3)
			assert_bool(slots.has(unit["slot"])).is_false()
			slots[unit["slot"]] = true
	var balance: Dictionary = GameData.load_balance()["run"]
	var max_rounds := int(balance["wins_to_victory"]) + int(balance["start_lives"]) - 1
	for r in range(1, max_rounds + 1):
		assert_bool(rounds.has(r)).override_failure_message("Kein Geisterteam für Runde %d" % r).is_true()


func test_json_integers_are_loaded_as_int() -> void:
	var def := MonsterDb.from_file().get_def("ember_pup")
	assert_int(typeof(def["cost"])).is_equal(TYPE_INT)
	assert_int(typeof(def["levels"][0]["hp"])).is_equal(TYPE_INT)
	assert_int(typeof(GameData.normalize_ints(0.5))).is_equal(TYPE_FLOAT)
