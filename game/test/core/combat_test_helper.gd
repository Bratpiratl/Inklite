class_name CombatTestHelper
extends RefCounted
## Baut kleine Test-Monster, damit Tests nicht an den echten Balancewerten hängen.


static func monster(id: String, hp: int, atk: int, ability: Dictionary = {}) -> Dictionary:
	var level := {"hp": hp, "atk": atk, "ability": ability if not ability.is_empty() else null}
	return {"id": id, "name": id, "type": "test", "rarity": 1, "cost": 1, "levels": [level]}


static func ability(trigger: String, effect: String, target: String, value: int) -> Dictionary:
	return {"trigger": trigger, "effect": effect, "target": target, "value": value}


static func rules(overrides: Dictionary = {}) -> Dictionary:
	var result := {"max_ticks": 40, "poison_decay_per_tick": 0, "poison_ignores_shield": true}
	result.merge(overrides, true)
	return result


static func sim(defs: Array, rule_overrides: Dictionary = {}) -> CombatSim:
	return CombatSim.new(MonsterDb.from_array(defs), rules(rule_overrides))


static func unit(id: String, slot: int, level: int = 1) -> Dictionary:
	return {"id": id, "level": level, "slot": slot}


static func events_of(result: Dictionary, ev: String) -> Array:
	return result["events"].filter(func(e: Dictionary) -> bool: return e["ev"] == ev)
