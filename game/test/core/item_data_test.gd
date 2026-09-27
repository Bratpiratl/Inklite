extends GdUnitTestSuite
## Prüft trainers.json und trinkets.json gegen den MVP-Umfang und die erlaubten Kombinationen.

const COMBAT_TRIGGERS := ["battle_start", "on_attack", "on_hurt", "on_death"]
const COMBAT_EFFECTS := ["poison", "shield", "damage", "buff_atk", "buff_hp"]
const COMBAT_TARGETS := ["self", "target", "attacker", "allies_all", "allies_row", "allies_front", "ally_random",
	"enemies_all", "enemies_front", "enemy_front", "enemy_random"]
## Ohne auslösendes Monster (Kampfstart) ergeben nur teamweite Ziele Sinn.
const TEAM_ONLY_TARGETS := ["allies_all", "allies_front", "ally_random", "enemies_all", "enemies_front", "enemy_random"]


func _all_items() -> Array:
	var items := ItemDb.from_files()
	var result: Array = []
	for id in items.trainer_ids():
		result.append(items.trainer(id))
	for id in items.trinket_ids():
		result.append(items.trinket(id))
	return result


func test_two_trainers_and_six_trinkets() -> void:
	var items := ItemDb.from_files()
	assert_int(items.trainer_ids().size()).is_equal(2)
	assert_int(items.trinket_ids().size()).is_equal(6)


func test_every_item_ability_is_valid() -> void:
	for def: Dictionary in _all_items():
		var a: Dictionary = def["ability"]
		var label: String = def["id"]
		assert_bool(ResourceLoader.exists("res://assets/sprites/" + def["sprite"])).override_failure_message("Sprite fehlt: " + label).is_true()
		if a["trigger"] == TeamAbility.TRIGGER_ROUND_END:
			assert_array(TeamAbility.SHOP_EFFECTS).override_failure_message(label).contains([a["effect"]])
			if a["effect"] != TeamAbility.EFFECT_GOLD:
				assert_array(TeamAbility.SHOP_TARGETS).override_failure_message(label).contains([a["target"]])
			continue
		assert_array(COMBAT_TRIGGERS).override_failure_message(label).contains([a["trigger"]])
		assert_array(COMBAT_EFFECTS).override_failure_message(label).contains([a["effect"]])
		assert_array(COMBAT_TARGETS).override_failure_message(label).contains([a["target"]])
		if a["trigger"] == "battle_start":
			assert_array(TEAM_ONLY_TARGETS).override_failure_message(label).contains([a["target"]])


func test_all_required_triggers_are_used() -> void:
	var used := {}
	for def: Dictionary in _all_items():
		used[def["ability"]["trigger"]] = true
	for trigger in ["battle_start", "on_attack", "on_death", "round_end"]:
		assert_bool(used.has(trigger)).override_failure_message("Kein Item mit " + trigger).is_true()
