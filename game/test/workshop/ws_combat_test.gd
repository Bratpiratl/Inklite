extends GdUnitTestSuite

const H := preload("res://test/workshop/ws_test_helper.gd")


func _mixed() -> WsRuleset:
	return H.ruleset([
		H.unit("a", 3, 4), H.unit("b", 2, 6, {"keywords": ["taunt"]}), H.unit("c", 5, 2),
		H.unit("d", 1, 3, {"abilities": [{"trigger": "on_death", "effect": "summon", "token": "tok", "times": 2}]}),
	], [H.unit("tok", 1, 1)])


# --- Grundregeln BG ---

func test_same_seed_gives_identical_battle() -> void:
	var team_a := [H.t("a", 0), H.t("c", 1), H.t("d", 2)]
	var team_b := [H.t("b", 0), H.t("d", 1), H.t("a", 2)]
	var first := H.combat(_mixed()).simulate(team_a, team_b, 99)
	var second := H.combat(_mixed()).simulate(team_a, team_b, 99)
	assert_str(JSON.stringify(first["events"])).is_equal(JSON.stringify(second["events"]))


func test_both_sides_deal_damage_in_bg() -> void:
	var rs := H.ruleset([H.unit("big", 3, 10), H.unit("small", 2, 2)])
	var result := H.combat(rs).simulate([H.t("big", 0)], [H.t("small", 0)], 1)
	assert_int(result["winner"]).is_equal(0)
	var hits_on_big := H.events_of(result, "damage").filter(func(e: Dictionary) -> bool: return e["uid"] == 1)
	assert_int(hits_on_big.size()).is_equal(1)
	assert_int(hits_on_big[0]["hp"]).is_equal(8)


func test_no_retaliation_in_grid() -> void:
	var rs := H.ruleset([H.unit("big", 3, 10), H.unit("small", 2, 2)])
	var result := H.combat(rs, "grid").simulate([H.t("big", 0)], [H.t("small", 0)], 3)
	assert_int(result["winner"]).is_equal(0)
	var hits_on_big := H.events_of(result, "damage").filter(func(e: Dictionary) -> bool: return e["uid"] == 1)
	assert_int(hits_on_big.size()).is_less_equal(1)


func test_more_units_attack_first() -> void:
	var rs := H.ruleset([H.unit("x", 1, 50)])
	for s in 10:
		var result := H.combat(rs).simulate([H.t("x", 0)], [H.t("x", 0), H.t("x", 1)], s)
		assert_int(H.events_of(result, "attack")[0]["side"]).is_equal(1)


func test_attackers_go_left_to_right() -> void:
	var rs := H.ruleset([H.unit("x", 1, 50)])
	var result := H.combat(rs).simulate([H.t("x", 0), H.t("x", 1), H.t("x", 2)], [H.t("x", 0), H.t("x", 1), H.t("x", 2)], 5)
	var mine := H.uids(result, 0)
	var order: Array = H.events_of(result, "attack").filter(func(e: Dictionary) -> bool: return e["side"] == 0).map(func(e: Dictionary) -> int: return e["uid"])
	assert_array(order.slice(0, 4)).is_equal([mine[0], mine[1], mine[2], mine[0]])


func test_taunt_is_attacked_first() -> void:
	var rs := H.ruleset([H.unit("hitter", 1, 100), H.unit("wall", 0, 50, {"keywords": ["taunt"]}), H.unit("soft", 0, 50)])
	for s in 10:
		var result := H.combat(rs).simulate([H.t("hitter", 0)], [H.t("soft", 0), H.t("wall", 1)], s)
		var wall_uid: int = H.uids(result, 1)[1]
		# Solange die Mauer lebt (50 HP, 1 Schaden je Treffer), trifft jeder Angriff sie.
		for e: Dictionary in H.events_of(result, "attack").slice(0, 10):
			assert_int(e["to"]).is_equal(wall_uid)


# --- Schlüsselwörter ---

func test_divine_shield_blocks_one_hit() -> void:
	var rs := H.ruleset([H.unit("hitter", 10, 100), H.unit("shielded", 0, 5, {"keywords": ["divine_shield"]})])
	var result := H.combat(rs).simulate([H.t("hitter", 0)], [H.t("shielded", 0)], 1)
	assert_int(H.events_of(result, "shield_lost").size()).is_equal(1)
	assert_int(H.events_of(result, "attack").size()).is_equal(2)
	assert_int(result["winner"]).is_equal(0)


func test_venomous_kills_and_is_used_up() -> void:
	# Erster Treffer tötet durch Gift, danach braucht die Schlange 80 Treffer für den zweiten Riesen.
	var rs := H.ruleset([H.unit("snake", 1, 100, {"keywords": ["venomous"]}), H.unit("giant", 0, 80)])
	var result := H.combat(rs).simulate([H.t("snake", 0)], [H.t("giant", 0), H.t("giant", 1)], 2)
	assert_int(result["winner"]).is_equal(0)
	assert_int(result["attacks"]).is_equal(81)


func test_windfury_attacks_twice_in_a_row() -> void:
	var rs := H.ruleset([H.unit("fast", 1, 50, {"keywords": ["windfury"]}), H.unit("slow", 1, 50)])
	var result := H.combat(rs).simulate([H.t("fast", 0), H.t("slow", 1)], [H.t("slow", 0)], 4)
	var sides: Array = H.events_of(result, "attack").map(func(e: Dictionary) -> int: return e["side"])
	assert_array(sides.slice(0, 3)).is_equal([0, 0, 1])


func test_reborn_comes_back_with_one_health() -> void:
	var rs := H.ruleset([H.unit("ghost", 1, 1, {"keywords": ["reborn"]}), H.unit("killer", 5, 100)])
	var result := H.combat(rs).simulate([H.t("ghost", 0)], [H.t("killer", 0)], 1)
	assert_int(H.events_of(result, "reborn").size()).is_equal(1)
	assert_int(H.events_of(result, "death").size()).is_equal(2)


func test_cleave_hits_neighbours() -> void:
	var rs := H.ruleset([H.unit("axe", 2, 100, {"keywords": ["cleave"]}), H.unit("dummy", 0, 10, {"keywords": ["taunt"]}), H.unit("side", 0, 10)])
	var result := H.combat(rs).simulate([H.t("axe", 0)], [H.t("side", 0), H.t("dummy", 1), H.t("side", 2)], 1)
	var first_attack_hits := H.events_of(result, "damage").slice(0, 3)
	assert_int(first_attack_hits.size()).is_equal(3)


# --- Fähigkeiten ---

func test_deathrattle_summons_tokens_that_fight() -> void:
	var rs := _mixed()
	var result := H.combat(rs).simulate([H.t("d", 0)], [H.t("a", 0)], 1)
	assert_int(H.events_of(result, "summon").size()).is_equal(2)


func test_deathrattle_twice_passive() -> void:
	var rs := H.ruleset([
		H.unit("d", 0, 1, {"abilities": [{"trigger": "on_death", "effect": "summon", "token": "tok"}]}),
		H.unit("titus", 0, 50, {"passives": ["deathrattle_twice"]}),
		H.unit("killer", 5, 100, {"keywords": ["taunt"]}),
	], [H.unit("tok", 0, 1)])
	var result := H.combat(rs).simulate([H.t("d", 0), H.t("titus", 1)], [H.t("killer", 0)], 1)
	var summons := H.events_of(result, "summon")
	assert_int(summons.size()).is_greater_equal(2)


func test_start_of_combat_damage_hits_everyone_else() -> void:
	var rs := H.ruleset([H.unit("bomb", 0, 20, {"abilities": [{"trigger": "start_of_combat", "effect": "damage", "target": "all_others", "value": 3}]}),
		H.unit("weak", 0, 3)])
	var result := H.combat(rs).simulate([H.t("bomb", 0), H.t("weak", 1)], [H.t("weak", 0), H.t("weak", 1)], 1)
	assert_int(H.events_of(result, "death").size()).is_equal(3)
	assert_int(result["winner"]).is_equal(0)


func test_avenge_fires_after_count() -> void:
	var rs := H.ruleset([
		H.unit("avenger", 0, 100, {"abilities": [{"trigger": "avenge", "count": 2, "effect": "buff", "target": "self", "atk": 10}]}),
		H.unit("fodder", 0, 1),
		H.unit("killer", 1, 100),
	])
	var result := H.combat(rs).simulate([H.t("fodder", 0), H.t("fodder", 1), H.t("avenger", 2)], [H.t("killer", 0)], 3)
	var buffs := H.events_of(result, "buff")
	assert_int(buffs.size()).is_equal(1)
	assert_int(buffs[0]["atk"]).is_equal(10)


func test_permanent_buff_is_reported_for_origin_slot() -> void:
	var rs := H.ruleset([H.unit("grower", 1, 50, {"abilities": [{"trigger": "on_attack", "effect": "buff", "target": "self", "atk": 2, "hp": 1, "permanent": true}]}),
		H.unit("dummy", 0, 2)])
	var result := H.combat(rs).simulate([H.t("grower", 3)], [H.t("dummy", 0)], 1)
	assert_dict(result["permanent"][0]).contains_keys([3])
	assert_int(result["permanent"][0][3]["atk"]).is_equal(2)


func test_level_scales_stats_and_ability_values() -> void:
	var rs := H.ruleset([H.unit("u", 2, 3, {"abilities": [{"trigger": "on_attack", "effect": "buff", "target": "self", "atk": 1, "times": 1}]})])
	var stats := rs.level_stats("u", 3)
	assert_int(stats["atk"]).is_equal(6)
	assert_int(stats["hp"]).is_equal(9)
	assert_int(stats["abilities"][0]["atk"]).is_equal(3)
	assert_int(stats["abilities"][0]["times"]).is_equal(3)


func test_color_filter_limits_targets() -> void:
	var rs := H.ruleset([
		H.unit("bird", 0, 10, {"abilities": [{"trigger": "start_of_combat", "effect": "buff", "target": "allies_all", "only": {"color": "rot"}, "atk": 5}]}),
		H.unit("red", 0, 10, {"colors": ["rot"]}), H.unit("blue", 0, 10, {"colors": ["blau"]}),
	])
	var result := H.combat(rs).simulate([H.t("bird", 0), H.t("red", 1), H.t("blue", 2)], [H.t("blue", 0)], 1)
	var buffs := H.events_of(result, "buff")
	assert_int(buffs.size()).is_equal(1)


# --- Raster ---

func test_grid_hits_front_row_first() -> void:
	var rs := H.ruleset([H.unit("hitter", 1, 100), H.unit("back", 0, 10), H.unit("front", 0, 10)])
	var result := H.combat(rs, "grid").simulate([H.t("hitter", 1)], [H.t("front", 2), H.t("back", 4)], 1)
	var front_uid: int = H.uids(result, 1)[0]
	assert_int(H.events_of(result, "attack")[0]["to"]).is_equal(front_uid)


# --- Statistik ---

func test_stats_count_effective_damage_kills_and_summons() -> void:
	var rs := H.ruleset([
		H.unit("caller", 1, 1, {"abilities": [{"trigger": "on_death", "effect": "summon", "token": "tok"}]}),
		H.unit("dummy", 0, 3), H.unit("biter", 1, 3), H.unit("big", 10, 100),
	], [H.unit("tok", 5, 1)])
	# big (10 Angriff) trifft dummy (3 HP): effektiv 3 Schaden, 1 Kill.
	var r1 := H.combat(rs).simulate([H.t("big", 0)], [H.t("dummy", 0)], 1)
	var big: Dictionary = r1["stats"][0][0]
	assert_int(big["damage"]).is_equal(3)
	assert_int(big["kills"]).is_equal(1)
	assert_int(r1["stats"][1][0]["taken"]).is_equal(3)
	# Spielstein-Schaden zählt für die Beschwörerin: biter (3 HP) wird nur von unserer Seite getroffen.
	var r2 := H.combat(rs).simulate([H.t("caller", 0)], [H.t("biter", 0)], 2)
	var totals := WsCombat.team_totals(r2["stats"][0])
	assert_int(totals.size()).is_equal(1)
	assert_str(totals[0]["id"]).is_equal("caller")
	assert_int(totals[0]["summons"]).is_equal(1)
	assert_int(totals[0]["damage"]).is_equal(3)


func test_stats_count_shields_popped() -> void:
	var rs := H.ruleset([H.unit("hitter", 3, 100), H.unit("shielded", 0, 3, {"keywords": ["divine_shield"]})])
	var r := H.combat(rs).simulate([H.t("hitter", 0)], [H.t("shielded", 0)], 1)
	assert_int(r["stats"][0][0]["shields_popped"]).is_equal(1)
	assert_int(r["stats"][0][0]["damage"]).is_equal(3)


func test_damage_to_allies_counts_separately() -> void:
	var rs := H.ruleset([H.unit("bomb", 0, 20, {"abilities": [{"trigger": "start_of_combat", "effect": "damage", "target": "all_others", "value": 3}]}),
		H.unit("weak", 0, 3)])
	var r := H.combat(rs).simulate([H.t("bomb", 0), H.t("weak", 1)], [H.t("weak", 0), H.t("weak", 1)], 1)
	var bomb: Dictionary = r["stats"][0][0]
	assert_int(bomb["damage"]).is_equal(6)
	assert_int(bomb["friendly_damage"]).is_equal(3)
