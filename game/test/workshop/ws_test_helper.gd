extends RefCounted
## Bausteine für Workshop-Tests. Die Tests brauchen keinen Regelsatz von der Platte.


static func rules(overrides: Dictionary = {}) -> Dictionary:
	var r := {
		"rarities": ["Common", "Uncommon", "Rare"],
		"colors": [{"id": "rot"}, {"id": "blau"}],
		"economy": {"income_by_day": [30, 35, 40], "income_growth_after": 5, "gold_carries_over": true,
			"reroll_cost": 3, "free_rerolls_per_day": 0, "sell_level_multiplier": [1, 3, 6], "sell_divisor": 2},
		"shop": {"slots": 5, "rank_start": 1, "rank_per_day": 1, "exclude_owned_max_level": true,
			"rarity_weights_by_rank": [[100, 0, 0], [50, 50, 0], [0, 0, 100]]},
		"board": {"team_slots": 6, "bench_slots": 4, "max_level": 3, "merge_counts": [3, 2], "merge_bonus": "max", "level_scale": [1, 2, 3]},
		"run": {"start_lives": 10, "wins_to_victory": 10, "max_days": 40, "life_loss_by_day": [1, 1, 2, 2, 3],
			"second_chance": true, "draw_result": "draw"},
		"combat": {"mode": "bg", "bg": {"max_units": 7, "max_attacks": 200}, "grid": {"cols": 3, "rows": 2, "max_ticks": 40}},
	}
	for key: String in overrides:
		r[key] = overrides[key]
	return r


static func unit(id: String, atk: int, hp: int, opts: Dictionary = {}) -> Dictionary:
	var def := {"id": id, "name": id, "rarity": 0, "cost": 10, "colors": [], "atk": atk, "hp": hp,
		"keywords": [], "passives": [], "abilities": []}
	for key: String in opts:
		def[key] = opts[key]
	return def


static func ruleset(units: Array, tokens: Array = [], rule_overrides: Dictionary = {}) -> WsRuleset:
	var rs := WsRuleset.new()
	rs.setup(rules(rule_overrides), {"units": units, "tokens": tokens})
	return rs


static func t(id: String, slot: int, level: int = 1) -> Dictionary:
	return {"id": id, "level": level, "slot": slot}


static func combat(rs: WsRuleset, mode: String = "bg") -> WsCombat:
	var sim := WsCombat.new(rs, mode)
	sim.trace = true
	return sim


static func events_of(result: Dictionary, ev: String) -> Array:
	return result["events"].filter(func(e: Dictionary) -> bool: return e["ev"] == ev)


## uid der Einheiten nach Seite und Platzreihenfolge, aus dem Start-Ereignis.
static func uids(result: Dictionary, side: int) -> Array:
	var start: Dictionary = events_of(result, "start")[0]
	return start["units"].filter(func(u: Dictionary) -> bool: return u["side"] == side).map(func(u: Dictionary) -> int: return u["uid"])
