extends GdUnitTestSuite
## Run-Logik mit eigenen, festen Regeln, damit Tests nicht an Balancewerten hängen.

const H := preload("res://test/core/combat_test_helper.gd")


func _db() -> MonsterDb:
	return MonsterDb.from_array([
		H.monster("cheap", 5, 1),
		H.monster("wall", 50, 0),
		{"id": "trio", "name": "trio", "type": "test", "rarity": 1, "cost": 1,
			"levels": [{"hp": 1, "atk": 1}, {"hp": 2, "atk": 2}, {"hp": 4, "atk": 4}]},
	])


func _balance(run_overrides: Dictionary = {}) -> Dictionary:
	var run := {
		"start_lives": 2, "wins_to_victory": 2, "gold_per_round": [10, 20], "reroll_cost": 1,
		"sell_value_by_level": [1, 3, 6], "merge_count": 3, "shop_size_by_round": [3],
		"rarity_weights_by_round": [[100]],
	}
	run.merge(run_overrides, true)
	return {"combat": H.rules(), "run": run}


func _run(ghosts: Array = [], overrides: Dictionary = {}) -> RunState:
	return RunState.create(_db(), _balance(overrides), ghosts, 42)


func _set_offers(run: RunState, ids: Array) -> void:
	run.offers = ids.duplicate()


func test_new_run_starts_with_rules() -> void:
	var run := _run()
	assert_int(run.round_number).is_equal(1)
	assert_int(run.gold).is_equal(10)
	assert_int(run.lives).is_equal(2)
	assert_int(run.offers.size()).is_equal(3)


func test_buy_places_front_first_and_costs_gold() -> void:
	var run := _run()
	_set_offers(run, ["cheap", "wall", "cheap"])
	var result := run.buy(1)
	assert_bool(result["ok"]).is_true()
	assert_int(result["slot"]).is_equal(0)
	assert_int(run.gold).is_equal(9)
	assert_str(run.offers[1]).is_equal("")
	assert_bool(run.buy(1)["ok"]).is_false()


func test_cannot_buy_without_gold() -> void:
	var run := _run()
	run.gold = 0
	_set_offers(run, ["cheap"])
	assert_bool(run.can_buy(0)).is_false()
	assert_bool(run.buy(0)["ok"]).is_false()


func test_three_copies_merge_to_level_two_on_front_slot() -> void:
	var run := _run()
	run.board[4] = {"id": "trio", "level": 1}
	run.board[2] = {"id": "trio", "level": 1}
	_set_offers(run, ["trio"])
	var result := run.buy(0)
	assert_array(result["merges"]).has_size(1)
	assert_dict(run.board[0]).is_equal({"id": "trio", "level": 2})
	assert_int(run.unit_count()).is_equal(1)
	assert_int(result["slot"]).is_equal(0)


func test_merges_chain_up_to_level_three() -> void:
	var run := _run()
	run.board[0] = {"id": "trio", "level": 2}
	run.board[1] = {"id": "trio", "level": 2}
	run.board[5] = {"id": "trio", "level": 1}
	run.board[6] = {"id": "trio", "level": 1}
	_set_offers(run, ["trio"])
	var result := run.buy(0)
	assert_array(result["merges"]).has_size(2)
	assert_dict(run.board[0]).is_equal({"id": "trio", "level": 3})
	assert_int(run.unit_count()).is_equal(1)


func test_level_three_does_not_merge_further() -> void:
	var run := _run()
	for slot in 3:
		run.board[slot] = {"id": "trio", "level": 3}
	_set_offers(run, ["cheap"])
	assert_array(run.buy(0)["merges"]).is_empty()
	assert_int(run.unit_count()).is_equal(4)


func test_full_board_only_allows_merging_buys() -> void:
	var run := _run()
	for slot in CombatSim.SLOTS:
		run.board[slot] = {"id": "wall", "level": 1}
	run.board[3] = {"id": "trio", "level": 1}
	run.board[7] = {"id": "trio", "level": 1}
	run.board[0] = {"id": "wall", "level": 2}
	run.board[1] = {"id": "wall", "level": 2}
	_set_offers(run, ["cheap", "trio"])
	assert_bool(run.can_buy(0)).is_false()
	assert_bool(run.can_buy(1)).is_true()
	var result := run.buy(1)
	assert_bool(result["ok"]).is_true()
	assert_dict(run.board[3]).is_equal({"id": "trio", "level": 2})
	assert_that(run.board[7]).is_null()


func test_sell_refunds_by_level_and_frees_slot() -> void:
	var run := _run()
	run.board[2] = {"id": "trio", "level": 2}
	var gold_before := run.gold
	assert_int(run.sell(2)).is_equal(3)
	assert_int(run.gold).is_equal(gold_before + 3)
	assert_that(run.board[2]).is_null()
	assert_int(run.sell(2)).is_equal(0)


func test_move_swaps_slots() -> void:
	var run := _run()
	run.board[0] = {"id": "cheap", "level": 1}
	run.board[8] = {"id": "wall", "level": 1}
	assert_bool(run.move(0, 8)).is_true()
	assert_str(run.board[0]["id"]).is_equal("wall")
	assert_str(run.board[8]["id"]).is_equal("cheap")
	assert_bool(run.move(4, 0)).is_false()


func test_reroll_costs_gold_and_changes_counter() -> void:
	var run := _run()
	var rolls_before := run.rolls
	assert_bool(run.reroll()).is_true()
	assert_int(run.gold).is_equal(9)
	assert_int(run.rolls).is_equal(rolls_before + 1)
	run.gold = 0
	assert_bool(run.reroll()).is_false()


func test_win_advances_round_and_resets_gold() -> void:
	var ghosts := [{"id": "g1", "round": 1, "team": [{"id": "cheap", "level": 1, "slot": 0}]}]
	var run := _run(ghosts)
	run.board[0] = {"id": "wall", "level": 1}
	run.board[1] = {"id": "cheap", "level": 1}
	run.gold = 3
	var result := run.fight()
	assert_str(result["result"]).is_equal("win")
	assert_str(result["ghost_id"]).is_equal("g1")
	assert_int(run.wins).is_equal(1)
	assert_int(run.round_number).is_equal(2)
	assert_int(run.gold).is_equal(20)


func test_loss_costs_life_and_zero_lives_ends_run() -> void:
	var ghosts := [{"id": "g1", "round": 1, "team": [{"id": "wall", "level": 1, "slot": 0}, {"id": "cheap", "level": 1, "slot": 1}]}]
	var run := _run(ghosts)
	assert_str(run.fight()["result"]).is_equal("loss")
	assert_int(run.lives).is_equal(1)
	assert_bool(run.is_over()).is_false()
	run.fight()
	assert_int(run.lives).is_equal(0)
	assert_bool(run.is_over()).is_true()
	assert_bool(run.is_victory()).is_false()


func test_victory_after_enough_wins() -> void:
	var ghosts := [{"id": "g1", "round": 1, "team": []}]
	var run := _run(ghosts)
	run.board[0] = {"id": "cheap", "level": 1}
	run.fight()
	run.fight()
	assert_bool(run.is_victory()).is_true()
	assert_bool(run.is_over()).is_true()
	# Nach dem letzten Kampf startet keine neue Runde mehr.
	assert_int(run.round_number).is_equal(2)


func test_ghost_is_picked_from_current_round_or_closest_below() -> void:
	var ghosts := [
		{"id": "r1", "round": 1, "team": []},
		{"id": "r3", "round": 3, "team": []},
	]
	var run := _run(ghosts, {"start_lives": 9, "wins_to_victory": 9})
	run.board[0] = {"id": "cheap", "level": 1}
	assert_str(run.fight()["ghost_id"]).is_equal("r1")
	assert_str(run.fight()["ghost_id"]).is_equal("r1")
	assert_str(run.fight()["ghost_id"]).is_equal("r3")
	assert_str(run.fight()["ghost_id"]).is_equal("r3")


func test_save_and_load_roundtrip_continues_identically() -> void:
	var ghosts := [{"id": "g1", "round": 1, "team": [{"id": "cheap", "level": 1, "slot": 0}]}]
	var run := _run(ghosts)
	run.board[4] = {"id": "trio", "level": 2}
	run.reroll()
	var copy := RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())), _db(), _balance(), ghosts)
	assert_dict(copy.to_dict()).is_equal(run.to_dict())
	copy.reroll()
	run.reroll()
	assert_array(copy.offers).is_equal(run.offers)
	assert_str(JSON.stringify(copy.fight()["events"])).is_equal(JSON.stringify(run.fight()["events"]))


func test_same_seed_same_run() -> void:
	var a := RunState.create(MonsterDb.from_file(), GameData.load_balance(), [], 5)
	var b := RunState.create(MonsterDb.from_file(), GameData.load_balance(), [], 5)
	assert_array(a.offers).is_equal(b.offers)
	a.reroll()
	b.reroll()
	assert_array(a.offers).is_equal(b.offers)
