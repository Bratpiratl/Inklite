extends GdUnitTestSuite
## Team-Fähigkeiten (Trainer, Trinkets) im Kampf: ein Test je Auslöser plus Filter.

const H := preload("res://test/core/combat_test_helper.gd")


func _defs() -> Array:
	var fire := H.monster("fire", 20, 1)
	fire["type"] = "feuer"
	var moss := H.monster("moss", 20, 1)
	moss["type"] = "moos"
	return [fire, moss, H.monster("dummy", 30, 0), H.monster("hitter", 50, 2), H.monster("weak", 1, 0)]


func _mod(id: String, ability: Dictionary) -> Dictionary:
	return TeamAbility.tagged(ability, id)


func _team_events(result: Dictionary, source: String) -> Array:
	return H.events_of(result, "ability").filter(func(e: Dictionary) -> bool: return e["source"] == source)


func test_battle_start_shields_front_row_only() -> void:
	var mod := _mod("oak", H.ability("battle_start", "shield", "allies_front", 2))
	var result := H.sim(_defs()).simulate(
		[H.unit("dummy", 1), H.unit("dummy", 2), H.unit("dummy", 4)], [H.unit("dummy", 0)], 1, [mod])
	var slots := H.events_of(result, "shield").map(func(e: Dictionary) -> int: return e["slot"])
	slots.sort()
	assert_array(slots).is_equal([1, 2])
	var fired := _team_events(result, "oak")
	assert_int(fired.size()).is_equal(1)
	assert_int(fired[0]["slot"]).is_equal(-1)


func test_on_attack_respects_when_filter() -> void:
	var mod := _mod("olm", {"trigger": "on_attack", "when": {"type": "moos"}, "effect": "poison", "target": "target", "value": 1})
	var result := H.sim(_defs(), {"max_ticks": 1}).simulate(
		[H.unit("moss", 0), H.unit("fire", 1)], [H.unit("dummy", 0), H.unit("dummy", 1)], 1, [mod])
	var fired := _team_events(result, "olm")
	assert_int(fired.size()).is_equal(1)
	assert_int(fired[0]["slot"]).is_equal(0)
	assert_int(H.events_of(result, "poison").size()).is_equal(1)


func test_on_hurt_only_for_front_row() -> void:
	var mod := _mod("thorns", {"trigger": "on_hurt", "when": {"row": 0}, "effect": "damage", "target": "attacker", "value": 1})
	var sim := H.sim(_defs(), {"max_ticks": 1})
	var front := sim.simulate([H.unit("dummy", 1)], [H.unit("hitter", 1)], 1, [mod])
	assert_int(_team_events(front, "thorns").size()).is_equal(1)
	# Steht vorne niemand mehr, wird die mittlere Reihe getroffen: kein Auslöser.
	var middle := sim.simulate([H.unit("dummy", 4)], [H.unit("hitter", 1)], 1, [mod])
	assert_int(_team_events(middle, "thorns").size()).is_equal(0)


func test_on_death_buffs_surviving_allies() -> void:
	var mod := _mod("soul", H.ability("on_death", "buff_atk", "allies_all", 1))
	var result := H.sim(_defs(), {"max_ticks": 1}).simulate(
		[H.unit("weak", 1), H.unit("dummy", 4)], [H.unit("hitter", 1)], 1, [mod])
	var buffs := H.events_of(result, "buff")
	assert_int(buffs.size()).is_equal(1)
	assert_int(buffs[0]["slot"]).is_equal(4)
	assert_str(buffs[0]["stat"]).is_equal("atk")
	assert_int(buffs[0]["atk"]).is_equal(1)


func test_only_filter_limits_targets() -> void:
	var mod := _mod("elixir", {"trigger": "battle_start", "effect": "buff_atk", "target": "allies_all", "only": {"type": "feuer"}, "value": 1})
	var result := H.sim(_defs(), {"max_ticks": 1}).simulate(
		[H.unit("fire", 0), H.unit("moss", 1), H.unit("fire", 5)], [H.unit("dummy", 0)], 1, [mod])
	var slots := H.events_of(result, "buff").map(func(e: Dictionary) -> int: return e["slot"])
	slots.sort()
	assert_array(slots).is_equal([0, 5])


func test_buff_hp_raises_hp_for_battle() -> void:
	var mod := _mod("herb", H.ability("battle_start", "buff_hp", "allies_all", 5))
	var result := H.sim(_defs(), {"max_ticks": 1}).simulate([H.unit("dummy", 0)], [H.unit("hitter", 0)], 1, [mod])
	assert_int(H.events_of(result, "buff")[0]["hp"]).is_equal(35)
	assert_int(H.events_of(result, "damage")[0]["hp"]).is_equal(33)


func test_bonus_stats_from_team_entry() -> void:
	var sim := H.sim(_defs(), {"max_ticks": 1})
	var result := sim.simulate([{"id": "dummy", "level": 1, "slot": 0, "atk_bonus": 3, "hp_bonus": 4}], [H.unit("dummy", 0)], 1)
	var start: Dictionary = H.events_of(result, "start")[0]["units"][0]
	assert_int(start["atk"]).is_equal(3)
	assert_int(start["hp"]).is_equal(34)


func test_enemy_side_abilities_stay_on_their_side() -> void:
	var mod := _mod("oak", H.ability("battle_start", "shield", "allies_all", 2))
	var result := H.sim(_defs(), {"max_ticks": 1}).simulate([H.unit("dummy", 0)], [H.unit("dummy", 0)], 1, [], [mod])
	var shields := H.events_of(result, "shield")
	assert_int(shields.size()).is_equal(1)
	assert_int(shields[0]["side"]).is_equal(1)


func test_matches_filter() -> void:
	assert_bool(TeamAbility.matches(null, "moos", 0)).is_true()
	assert_bool(TeamAbility.matches({"type": "moos"}, "moos", 2)).is_true()
	assert_bool(TeamAbility.matches({"type": "moos", "row": 0}, "moos", 2)).is_false()
	assert_bool(TeamAbility.matches({"tpye": "moos"}, "moos", 0)).is_false()
