extends GdUnitTestSuite
## Prüft data/monsters.json gegen den MVP-Umfang aus PLAN.md.

const TRIGGERS := ["battle_start", "on_attack", "on_hurt", "on_death"]
const EFFECTS := ["poison", "shield", "damage"]
const TARGETS := ["self", "target", "attacker", "allies_all", "allies_row", "enemies_all", "enemies_front", "enemy_front", "enemy_random"]


func _defs() -> Array:
	return GameData.load_json(GameData.MONSTERS_PATH)


func test_twelve_monsters_four_types_three_rarities() -> void:
	var defs := _defs()
	assert_int(defs.size()).is_equal(12)
	var per_type := {}
	var rarities := {}
	for def: Dictionary in defs:
		per_type[def["type"]] = per_type.get(def["type"], 0) + 1
		rarities[int(def["rarity"])] = true
	assert_int(per_type.size()).is_equal(4)
	for count: int in per_type.values():
		assert_int(count).is_equal(3)
	assert_array(rarities.keys()).contains_exactly_in_any_order([1, 2, 3])


func test_ids_are_unique() -> void:
	var ids := {}
	for def: Dictionary in _defs():
		assert_bool(ids.has(def["id"])).is_false()
		ids[def["id"]] = true


func test_every_monster_has_three_valid_levels() -> void:
	for def: Dictionary in _defs():
		var levels: Array = def["levels"]
		assert_int(levels.size()).is_equal(3)
		for level: Dictionary in levels:
			assert_int(int(level["hp"])).is_greater(0)
			assert_int(int(level["atk"])).is_greater_equal(0)
			var ability: Variant = level.get("ability")
			if ability is Dictionary:
				assert_array(TRIGGERS).contains([ability["trigger"]])
				assert_array(EFFECTS).contains([ability["effect"]])
				assert_array(TARGETS).contains([ability["target"]])
