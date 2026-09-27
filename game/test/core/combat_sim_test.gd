extends GdUnitTestSuite

const H := preload("res://test/core/combat_test_helper.gd")


func _real_sim() -> CombatSim:
	return CombatSim.new(MonsterDb.from_file(), GameData.load_balance()["combat"])


func _mixed_team_a() -> Array:
	return [H.unit("thorn_golem", 1), H.unit("ember_pup", 0), H.unit("spark_ferret", 4), H.unit("storm_lynx", 7)]


func _mixed_team_b() -> Array:
	return [H.unit("tide_crab", 1), H.unit("bolt_bat", 2), H.unit("spore_moth", 3), H.unit("deep_whale", 6), H.unit("moss_toad", 0)]


func _attacks_by(result: Dictionary, side: int) -> Array:
	return H.events_of(result, "attack").filter(func(e: Dictionary) -> bool: return e["side"] == side)


# --- Determinismus ---

func test_same_seed_gives_identical_battle() -> void:
	var first := _real_sim().simulate(_mixed_team_a(), _mixed_team_b(), 4242)
	var second := _real_sim().simulate(_mixed_team_a(), _mixed_team_b(), 4242)
	assert_int(first["winner"]).is_equal(second["winner"])
	assert_int(first["ticks"]).is_equal(second["ticks"])
	assert_str(JSON.stringify(first["events"])).is_equal(JSON.stringify(second["events"]))


func test_same_sim_instance_is_reusable() -> void:
	var sim := _real_sim()
	var first := sim.simulate(_mixed_team_a(), _mixed_team_b(), 7)
	sim.simulate(_mixed_team_b(), _mixed_team_a(), 99)
	var again := sim.simulate(_mixed_team_a(), _mixed_team_b(), 7)
	assert_str(JSON.stringify(again["events"])).is_equal(JSON.stringify(first["events"]))


func test_different_seeds_can_differ() -> void:
	# Zwei Ziele gleich weit entfernt: der Seed entscheidet, wer getroffen wird.
	var sim := H.sim([H.monster("hitter", 50, 1), H.monster("wall", 50, 0)])
	var targets := {}
	for s in 20:
		var result := sim.simulate([H.unit("hitter", 1)], [H.unit("wall", 0), H.unit("wall", 2)], s)
		targets[_attacks_by(result, 0)[0]["to_slot"]] = true
	assert_int(targets.size()).is_equal(2)


# --- Gift ---

func test_poison_ticks_every_tick_end() -> void:
	var sim := H.sim([
		H.monster("poisoner", 50, 0, H.ability("battle_start", "poison", "enemies_all", 2)),
		H.monster("dummy", 10, 0),
	])
	var result := sim.simulate([H.unit("poisoner", 0)], [H.unit("dummy", 0)], 1)
	var ticks := H.events_of(result, "damage").filter(func(e: Dictionary) -> bool: return e["kind"] == "poison")
	assert_int(ticks.size()).is_equal(5)
	assert_array(ticks.map(func(e: Dictionary) -> int: return e["hp"])).is_equal([8, 6, 4, 2, 0])
	assert_array(ticks.map(func(e: Dictionary) -> int: return e["t"])).is_equal([1, 2, 3, 4, 5])
	assert_int(result["winner"]).is_equal(0)
	assert_int(result["ticks"]).is_equal(5)


func test_poison_stacks() -> void:
	var sim := H.sim([
		H.monster("stinger", 50, 0, H.ability("on_attack", "poison", "target", 1)),
		H.monster("dummy", 100, 0),
	])
	var result := sim.simulate([H.unit("stinger", 0)], [H.unit("dummy", 0)], 1)
	var poison_hits := H.events_of(result, "damage").filter(func(e: Dictionary) -> bool: return e["kind"] == "poison")
	assert_array(poison_hits.slice(0, 3).map(func(e: Dictionary) -> int: return e["amount"])).is_equal([1, 2, 3])


func test_poison_decays_when_configured() -> void:
	var sim := H.sim([
		H.monster("poisoner", 50, 0, H.ability("battle_start", "poison", "enemies_all", 3)),
		H.monster("dummy", 20, 0),
	], {"poison_decay_per_tick": 1, "max_ticks": 6})
	var result := sim.simulate([H.unit("poisoner", 0)], [H.unit("dummy", 0)], 1)
	var hits := H.events_of(result, "damage")
	assert_array(hits.map(func(e: Dictionary) -> int: return e["amount"])).is_equal([3, 2, 1])
	# Das Ereignis meldet den Giftstand nach dem Abklingen, damit die Anzeige ihn nicht nachrechnen muss.
	assert_array(hits.map(func(e: Dictionary) -> int: return e["poison"])).is_equal([2, 1, 0])
	assert_int(result["winner"]).is_equal(CombatSim.DRAW)


func test_poison_ignores_shield_by_rule() -> void:
	var defs := [
		H.monster("poisoner", 50, 0, H.ability("battle_start", "poison", "enemies_all", 2)),
		H.monster("turtle", 10, 0, H.ability("battle_start", "shield", "self", 5)),
	]
	var through := H.sim(defs).simulate([H.unit("poisoner", 0)], [H.unit("turtle", 0)], 1)
	var first: Dictionary = H.events_of(through, "damage")[0]
	assert_int(first["amount"]).is_equal(2)
	assert_int(first["blocked"]).is_equal(0)

	var blocked := H.sim(defs, {"poison_ignores_shield": false}).simulate([H.unit("poisoner", 0)], [H.unit("turtle", 0)], 1)
	first = H.events_of(blocked, "damage")[0]
	assert_int(first["amount"]).is_equal(0)
	assert_int(first["blocked"]).is_equal(2)


# --- Schild ---

func test_shield_blocks_attack_damage() -> void:
	var sim := H.sim([
		H.monster("turtle", 10, 0, H.ability("battle_start", "shield", "self", 5)),
		H.monster("hitter", 50, 3),
	])
	var result := sim.simulate([H.unit("turtle", 0)], [H.unit("hitter", 0)], 1)
	var hits := H.events_of(result, "damage")
	assert_int(hits[0]["blocked"]).is_equal(3)
	assert_int(hits[0]["amount"]).is_equal(0)
	assert_int(hits[0]["hp"]).is_equal(10)
	assert_int(hits[0]["shield"]).is_equal(2)
	assert_int(hits[1]["blocked"]).is_equal(2)
	assert_int(hits[1]["amount"]).is_equal(1)
	assert_int(hits[1]["hp"]).is_equal(9)
	assert_int(hits[1]["shield"]).is_equal(0)


func test_shield_on_allies_row_only_hits_own_row() -> void:
	var sim := H.sim([
		H.monster("crab", 10, 0, H.ability("battle_start", "shield", "allies_row", 2)),
		H.monster("dummy", 10, 0),
	])
	var result := sim.simulate([H.unit("crab", 1), H.unit("dummy", 0), H.unit("dummy", 3)], [H.unit("dummy", 0)], 1)
	var shielded := H.events_of(result, "shield").map(func(e: Dictionary) -> int: return e["slot"])
	shielded.sort()
	assert_array(shielded).is_equal([0, 1])


# --- Raster und Auslöser ---

func test_front_row_is_hit_first() -> void:
	var sim := H.sim([H.monster("hitter", 50, 1), H.monster("dummy", 5, 0)])
	var result := sim.simulate([H.unit("hitter", 0)], [H.unit("dummy", 6), H.unit("dummy", 1)], 1)
	var attacks := _attacks_by(result, 0)
	for i in 5:
		assert_int(attacks[i]["to_slot"]).is_equal(1)
	assert_int(attacks[5]["to_slot"]).is_equal(6)


func test_slot_order_and_alternating_initiative() -> void:
	var sim := H.sim([H.monster("hitter", 50, 1)])
	var result := sim.simulate([H.unit("hitter", 3), H.unit("hitter", 0)], [H.unit("hitter", 0)], 1)
	var order := H.events_of(result, "attack").slice(0, 6).map(
		func(e: Dictionary) -> String: return "%d:%d" % [e["side"], e["slot"]])
	# Tick 1: Seite A hat Vorzug, Tick 2: Seite B.
	assert_array(order).is_equal(["0:0", "1:0", "0:3", "1:0", "0:0", "0:3"])


func test_on_death_fires_after_dying() -> void:
	var sim := H.sim([
		H.monster("bomb", 1, 0, H.ability("on_death", "damage", "enemies_all", 4)),
		H.monster("hitter", 10, 1),
	])
	var result := sim.simulate([H.unit("bomb", 0)], [H.unit("hitter", 0), H.unit("hitter", 1)], 1)
	var ability := H.events_of(result, "ability")
	assert_int(ability.size()).is_equal(1)
	assert_str(ability[0]["trigger"]).is_equal("on_death")
	var ability_hits := H.events_of(result, "damage").filter(func(e: Dictionary) -> bool: return e["kind"] == "ability")
	assert_int(ability_hits.size()).is_equal(2)
	assert_int(ability_hits[0]["hp"]).is_equal(6)


func test_on_hurt_reacts_only_to_attacks() -> void:
	var sim := H.sim([
		H.monster("thorns", 30, 0, H.ability("on_hurt", "damage", "attacker", 1)),
		H.monster("hitter", 30, 2),
	])
	var result := sim.simulate([H.unit("thorns", 0), H.unit("thorns", 1)], [H.unit("hitter", 0)], 1)
	var retaliations := H.events_of(result, "damage").filter(func(e: Dictionary) -> bool: return e["kind"] == "ability")
	# Ein tödlicher Treffer löst kein on_hurt mehr aus.
	var survived_hits := H.events_of(result, "damage").filter(
		func(e: Dictionary) -> bool: return e["kind"] == "attack" and e["side"] == 0 and e["hp"] > 0)
	assert_int(retaliations.size()).is_greater(0)
	assert_int(retaliations.size()).is_equal(survived_hits.size())


func test_draw_when_nobody_can_win() -> void:
	var sim := H.sim([H.monster("dummy", 5, 0)], {"max_ticks": 7})
	var result := sim.simulate([H.unit("dummy", 0)], [H.unit("dummy", 0)], 1)
	assert_int(result["winner"]).is_equal(CombatSim.DRAW)
	assert_int(result["ticks"]).is_equal(7)


func test_empty_team_loses_immediately() -> void:
	var sim := H.sim([H.monster("dummy", 5, 0)])
	var result := sim.simulate([H.unit("dummy", 0)], [], 1)
	assert_int(result["winner"]).is_equal(0)
	assert_int(result["ticks"]).is_equal(0)


func test_events_end_with_end_event() -> void:
	var result := _real_sim().simulate(_mixed_team_a(), _mixed_team_b(), 3)
	var events: Array = result["events"]
	assert_str(events[0]["ev"]).is_equal("start")
	assert_str(events[-1]["ev"]).is_equal("end")
	assert_int(events[-1]["winner"]).is_equal(result["winner"])
