extends GdUnitTestSuite
## RunLogger: Format der Zeilen wie in PLAN.md, gleich für Bots und echte Runs.

const H := preload("res://test/core/combat_test_helper.gd")

var _lines: Array = []


func _balance() -> Dictionary:
	return {"combat": H.rules(), "run": {
		"start_lives": 1, "wins_to_victory": 3, "gold_per_round": [10], "reroll_cost": 1,
		"sell_value_by_level": [1, 3, 6], "merge_count": 3, "shop_size_by_round": [3],
		"rarity_weights_by_round": [[100]],
	}}


func _run() -> RunState:
	_lines = []
	var db := MonsterDb.from_array([H.monster("cheap", 5, 1), H.monster("wall", 50, 3)])
	var ghosts := [{"id": "g1", "round": 1, "team": [{"id": "wall", "level": 1, "slot": 0}]}]
	var run := RunState.create(db, _balance(), ghosts, 7)
	run.logger = RunLogger.new({"run": "test", "v": "9.9"}, func(line: Dictionary) -> void: _lines.append(line))
	return run


func _events(ev: String) -> Array:
	return _lines.filter(func(l: Dictionary) -> bool: return l["ev"] == ev)


func test_shop_event_lists_offered_and_bought_per_roll() -> void:
	var run := _run()
	var first_offers := run.offers.duplicate()
	run.buy(0)
	run.reroll()
	var shops := _events("shop")
	assert_int(shops.size()).is_equal(1)
	assert_array(shops[0]["offered"]).is_equal(first_offers)
	assert_array(shops[0]["bought"]).is_equal([first_offers[0]])
	assert_str(shops[0]["run"]).is_equal("test")
	assert_str(shops[0]["v"]).is_equal("9.9")
	assert_int(shops[0]["round"]).is_equal(1)


func test_battle_and_run_end_events() -> void:
	var run := _run()
	run.board[0] = {"id": "cheap", "level": 1}
	run.fight()
	# Shop der Runde wird vor dem Kampf abgeschlossen.
	assert_int(_events("shop").size()).is_equal(1)
	var battle: Dictionary = _events("battle")[0]
	assert_array(battle["team"]).is_equal(["cheap:1"])
	assert_str(battle["enemy"]).is_equal("g1")
	assert_str(battle["result"]).is_equal("loss")
	assert_bool(battle.has("seed")).is_true()
	assert_float(battle["duration_s"]).is_greater(0.0)
	var end: Dictionary = _events("run_end")[0]
	assert_int(end["wins"]).is_equal(0)
	assert_int(end["lives"]).is_equal(0)
	assert_bool(end["victory"]).is_false()


func test_sell_event() -> void:
	var run := _run()
	run.board[3] = {"id": "wall", "level": 2}
	run.sell(3)
	var sell: Dictionary = _events("sell")[0]
	assert_str(sell["unit"]).is_equal("wall:2")
	assert_int(sell["value"]).is_equal(3)


func test_lines_are_valid_json() -> void:
	var run := _run()
	run.board[0] = {"id": "cheap", "level": 1}
	run.fight()
	for line: Dictionary in _lines:
		assert_that(JSON.parse_string(JSON.stringify(line))).is_not_null()
