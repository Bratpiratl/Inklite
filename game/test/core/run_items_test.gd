extends GdUnitTestSuite
## Trainer, Trinkets und round_end im Run.

const H := preload("res://test/core/combat_test_helper.gd")


func _db() -> MonsterDb:
	var zap := H.monster("zap", 5, 1)
	zap["type"] = "blitz"
	return MonsterDb.from_array([H.monster("cheap", 5, 1), zap,
		{"id": "trio", "name": "trio", "type": "blitz", "rarity": 1, "cost": 1,
			"levels": [{"hp": 1, "atk": 1}, {"hp": 2, "atk": 2}, {"hp": 4, "atk": 4}]}])


func _items() -> ItemDb:
	return ItemDb.from_arrays(
		[
			{"id": "smith", "ability": {"trigger": "round_end", "effect": "buff_atk", "target": "ally_random", "only": {"type": "blitz"}, "value": 1}},
			{"id": "banker", "ability": {"trigger": "round_end", "effect": "gold", "value": 2}},
		],
		[
			{"id": "t1", "ability": H.ability("battle_start", "shield", "allies_all", 1)},
			{"id": "t2", "ability": H.ability("battle_start", "shield", "allies_all", 1)},
			{"id": "t3", "ability": H.ability("battle_start", "shield", "allies_all", 1)},
			{"id": "t4", "ability": H.ability("battle_start", "shield", "allies_all", 1)},
		])


func _balance() -> Dictionary:
	return {"combat": H.rules(), "run": {
		"start_lives": 3, "wins_to_victory": 10, "gold_per_round": [10], "reroll_cost": 1,
		"sell_value_by_level": [1, 3, 6], "merge_count": 3, "shop_size_by_round": [3],
		"rarity_weights_by_round": [[100]], "trinket_every_wins": 2, "trinket_choices": 3,
	}}


func _ghosts_empty() -> Array:
	return [{"id": "g", "round": 1, "team": []}]


func _run(trainer: String) -> RunState:
	return RunState.create(_db(), _balance(), _ghosts_empty(), 3, trainer, _items())


func test_trainer_is_part_of_team_abilities() -> void:
	var run := _run("smith")
	var abilities := run.team_abilities()
	assert_int(abilities.size()).is_equal(1)
	assert_str(abilities[0]["id"]).is_equal("smith")


func test_round_end_gold_is_paid_next_round() -> void:
	var run := _run("banker")
	run.board[0] = {"id": "cheap", "level": 1}
	var result := run.fight()
	assert_array(result["round_end"]).has_size(1)
	assert_int(run.gold).is_equal(12)


func test_round_end_buff_is_permanent_and_filtered() -> void:
	var run := _run("smith")
	run.board[0] = {"id": "cheap", "level": 1}
	run.board[4] = {"id": "zap", "level": 1}
	var result := run.fight()
	assert_int(result["round_end"][0]["slot"]).is_equal(4)
	assert_int(run.board[4]["atk_bonus"]).is_equal(1)
	assert_bool(run.board[0].has("atk_bonus")).is_false()
	# Der Bonus zählt im Kampf mit.
	var start_units: Array = H.events_of(result, "start")[0]["units"]
	var zap: Dictionary = start_units.filter(func(u: Dictionary) -> bool: return u["slot"] == 4)[0]
	assert_int(zap["atk"]).is_equal(2)
	run.fight()
	assert_int(run.board[4]["atk_bonus"]).is_equal(2)


func test_bonuses_add_up_when_merging() -> void:
	var run := _run("")
	run.board[0] = {"id": "trio", "level": 1, "atk_bonus": 2}
	run.board[1] = {"id": "trio", "level": 1, "hp_bonus": 1}
	run.offers = ["trio"]
	run.buy(0)
	assert_dict(run.board[0]).is_equal({"id": "trio", "level": 2, "atk_bonus": 2, "hp_bonus": 1})


func test_trinket_choice_after_every_second_win() -> void:
	var run := _run("")
	run.board[0] = {"id": "cheap", "level": 1}
	run.fight()
	assert_array(run.pending_trinkets).is_empty()
	run.fight()
	assert_int(run.pending_trinkets.size()).is_equal(3)
	assert_bool(run.can_fight()).is_false()
	assert_dict(run.fight()).is_empty()
	var pick: String = run.pending_trinkets[1]
	assert_bool(run.choose_trinket("unbekannt")).is_false()
	assert_bool(run.choose_trinket(pick)).is_true()
	assert_array(run.trinkets).is_equal([pick])
	assert_bool(run.can_fight()).is_true()
	run.fight()
	run.fight()
	# Bereits gewählte Trinkets werden nicht noch einmal angeboten.
	assert_bool(run.pending_trinkets.has(pick)).is_false()
	assert_int(run.pending_trinkets.size()).is_equal(3)


func test_trinket_abilities_reach_combat() -> void:
	var run := _run("")
	run.trinkets.append("t1")
	run.board[0] = {"id": "cheap", "level": 1}
	var result := run.fight()
	assert_int(H.events_of(result, "shield").size()).is_equal(1)


func test_save_and_load_keeps_items() -> void:
	var run := _run("smith")
	run.trinkets.append("t2")
	run.pending_trinkets.append("t3")
	run.bonus_gold = 4
	run.board[2] = {"id": "zap", "level": 1, "atk_bonus": 3}
	var copy := RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())), _db(), _balance(), _ghosts_empty(), _items())
	assert_dict(copy.to_dict()).is_equal(GameData.normalize_ints(JSON.parse_string(JSON.stringify(run.to_dict()))))
	assert_str(copy.trainer).is_equal("smith")
	assert_int(copy.team_abilities().size()).is_equal(2)
