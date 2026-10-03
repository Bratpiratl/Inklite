extends GdUnitTestSuite

const H := preload("res://test/workshop/ws_test_helper.gd")


func _rs() -> WsRuleset:
	return H.ruleset([
		H.unit("c1", 2, 2, {"rarity": 0, "cost": 10}),
		H.unit("c2", 2, 3, {"rarity": 0, "cost": 15, "colors": ["rot"]}),
		H.unit("u1", 3, 3, {"rarity": 1, "cost": 25}),
		H.unit("r1", 4, 4, {"rarity": 2, "cost": 35}),
		H.unit("buffer", 1, 1, {"rarity": 2, "cost": 30,
			"abilities": [{"trigger": "on_buy", "effect": "buff", "target": "allies_other", "atk": 2, "hp": 1}]}),
		H.unit("seller", 1, 1, {"rarity": 2, "cost": 30,
			"abilities": [{"trigger": "on_sell", "effect": "buff", "target": "allies_all", "atk": 1}]}),
	])


func _offer(run: WsRun, index: int, id: String) -> void:
	run.offers[index] = {"id": id, "cost": run.rs.cost(id)}


func test_first_day_income_and_shop() -> void:
	var run := WsRun.create(_rs(), 1)
	assert_int(run.gold).is_equal(30)
	assert_int(run.offers.size()).is_equal(5)
	for offer: Dictionary in run.offers:
		assert_int(run.rs.get_def(offer["id"])["rarity"]).is_equal(0)


func test_income_grows_after_list() -> void:
	var rs := _rs()
	assert_int(rs.income_for_day(3)).is_equal(40)
	assert_int(rs.income_for_day(5)).is_equal(50)


func test_rank_follows_day_and_falls_back_to_lower_rarity() -> void:
	var rs := _rs()
	assert_int(rs.rank_for_day(3)).is_equal(3)
	assert_array(rs.rarity_weights(3)).is_equal([0, 0, 100])
	assert_array(rs.rarity_weights(9)).is_equal([0, 0, 100])


func test_buy_pays_price_and_places_in_team() -> void:
	var run := WsRun.create(_rs(), 1)
	_offer(run, 0, "c2")
	assert_bool(run.buy(0, 2)["ok"]).is_true()
	assert_int(run.gold).is_equal(15)
	assert_str(run.team[2]["id"]).is_equal("c2")
	assert_object(run.offers[0]).is_null()


func test_three_copies_merge_to_level_two() -> void:
	var run := WsRun.create(_rs(), 1)
	run.gold = 100
	for i in 3:
		_offer(run, i, "c1")
	for i in 3:
		run.buy(i)
	var units := run.owned_units()
	assert_int(units.size()).is_equal(1)
	assert_int(units[0]["level"]).is_equal(2)


func test_two_level_two_merge_to_level_three() -> void:
	var run := WsRun.create(_rs(), 1)
	run.team[0] = {"id": "c1", "level": 2, "atk_bonus": 1, "hp_bonus": 0, "keywords": []}
	run.bench[0] = {"id": "c1", "level": 1, "atk_bonus": 0, "hp_bonus": 4, "keywords": ["taunt"]}
	run.bench[1] = {"id": "c1", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	run.gold = 100
	_offer(run, 0, "c1")
	run.buy(0)
	var units := run.owned_units()
	assert_int(units.size()).is_equal(1)
	assert_int(units[0]["level"]).is_equal(3)
	# Batomon-Regel: von Boni bleibt je Wert der stärkste, Schlüsselwörter werden vereint.
	assert_int(units[0]["atk_bonus"]).is_equal(1)
	assert_int(units[0]["hp_bonus"]).is_equal(4)
	assert_array(units[0]["keywords"]).contains(["taunt"])


func test_merge_works_with_full_board() -> void:
	var run := WsRun.create(_rs(), 1)
	for i in run.team.size():
		run.team[i] = {"id": "r1", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []} if i > 1 else null
	run.team[0] = {"id": "c1", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	run.team[1] = {"id": "c1", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	for i in run.bench.size():
		run.bench[i] = {"id": "u1", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	run.gold = 100
	_offer(run, 0, "c1")
	assert_bool(run.can_buy(0)).is_true()
	run.buy(0)
	assert_int(run.team[0]["level"]).is_equal(2)


func test_sell_value_formula() -> void:
	var rs := _rs()
	assert_int(rs.sell_value("c2", 1)).is_equal(8)   # ceil(15 / 2)
	assert_int(rs.sell_value("c2", 2)).is_equal(23)  # ceil(45 / 2)
	assert_int(rs.sell_value("c1", 3)).is_equal(30)  # 60 / 2


func test_battlecry_buffs_team_permanently() -> void:
	var run := WsRun.create(_rs(), 1)
	run.gold = 100
	_offer(run, 0, "c1")
	run.buy(0)
	_offer(run, 1, "buffer")
	run.buy(1)
	assert_int(run.team[0]["atk_bonus"]).is_equal(2)
	assert_int(run.team[0]["hp_bonus"]).is_equal(1)
	assert_int(run.team[1]["atk_bonus"]).is_equal(0)


func test_sell_trigger_does_not_buff_itself() -> void:
	var run := WsRun.create(_rs(), 1)
	run.team[0] = {"id": "c1", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	run.team[1] = {"id": "seller", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	run.sell(WsRun.TEAM, 1)
	assert_int(run.team[0]["atk_bonus"]).is_equal(1)
	assert_object(run.team[1]).is_null()


func test_lock_keeps_offers_for_next_day() -> void:
	var run := WsRun.create(_rs(), 3)
	var before: Array = run.offers.map(func(o: Variant) -> String: return o["id"])
	run.toggle_lock()
	run.fight({"id": "leer", "team": []})
	var after: Array = run.offers.map(func(o: Variant) -> String: return o["id"])
	assert_array(after).is_equal(before)


func test_loss_costs_lives_by_day_and_second_chance() -> void:
	var rs := _rs()
	var run := WsRun.create(rs, 1)
	run.day = 5
	run.lives = 3
	run.team[0] = {"id": "c1", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	var strong := {"id": "boss", "team": [{"id": "r1", "level": 3, "slot": 0}]}
	run.fight(strong)
	assert_str(run.last_battle["result"]).is_equal("loss")
	assert_int(run.lives).is_equal(1)  # 3 - 3 = 0, Second Chance setzt auf 1
	assert_bool(run.second_chance_used).is_true()
	run.fight(strong)
	assert_bool(run.is_over()).is_true()


func test_win_against_empty_team_and_carry_over_gold() -> void:
	var run := WsRun.create(_rs(), 1)
	run.team[0] = {"id": "c1", "level": 1, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	run.fight({"id": "leer", "team": []})
	assert_int(run.wins).is_equal(1)
	assert_int(run.gold).is_equal(65)  # 30 nicht ausgegeben + 35


func test_maxed_species_no_longer_offered() -> void:
	var run := WsRun.create(_rs(), 1)
	run.team[0] = {"id": "c1", "level": 3, "atk_bonus": 0, "hp_bonus": 0, "keywords": []}
	for i in 20:
		run.gold = 10
		run.reroll()
		for offer: Variant in run.offers:
			if offer != null:
				assert_str(offer["id"]).is_not_equal("c1")


func test_same_seed_same_run() -> void:
	var rs := _rs()
	var a := WsRun.create(rs, 42)
	var b := WsRun.create(rs, 42)
	assert_str(JSON.stringify(a.offers)).is_equal(JSON.stringify(b.offers))


func test_ghost_pool_filters_bots_and_matches_wins() -> void:
	var rs := H.ruleset([H.unit("c1", 1, 1)], [], {"run": {"start_lives": 10, "wins_to_victory": 10, "max_days": 40,
		"life_loss_by_day": [1], "ghost_bots": ["greedy"], "ghost_match_pool": 2, "ghost_day_offset": 1}})
	rs.ghosts = [
		{"id": "r", "day": 4, "wins": 3, "bot": "random", "team": []},
		{"id": "g0", "day": 4, "wins": 0, "bot": "greedy", "team": []},
		{"id": "g3", "day": 4, "wins": 3, "bot": "greedy", "team": []},
		{"id": "g4", "day": 4, "wins": 4, "bot": "greedy", "team": []},
		{"id": "early", "day": 3, "wins": 3, "bot": "greedy", "team": []},
	]
	# Tag 3 + Versatz 1 = Tag 4, nur greedy, die zwei mit der ähnlichsten Siegzahl zu 3.
	var ids: Array = rs.ghost_pool(3, 3).map(func(g: Dictionary) -> String: return g["id"])
	ids.sort()
	assert_array(ids).is_equal(["g3", "g4"])
