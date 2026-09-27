class_name Effects
extends RefCounted
## Effekte von Fähigkeiten und der Schadensweg. Ein Effekt ist nur ein Name in den Daten,
## der hier auf eine Funktion zeigt. Neue Monster brauchen so meist keinen neuen Code.

const POISON := "poison"
const SHIELD := "shield"
const DAMAGE := "damage"
const BUFF_ATK := "buff_atk"
const BUFF_HP := "buff_hp"

## Herkunft von Schaden. on_hurt löst nur bei ATTACK aus, sonst könnten sich zwei
## Vergelter endlos gegenseitig treffen.
const KIND_ATTACK := "attack"
const KIND_ABILITY := "ability"
const KIND_POISON := "poison"


static func apply(sim: CombatSim, effect: String, value: int, source: CombatUnit, targets: Array[CombatUnit]) -> void:
	for target in targets:
		match effect:
			POISON:
				add_poison(sim, target, value)
			SHIELD:
				add_shield(sim, target, value)
			DAMAGE:
				deal_damage(sim, source, target, value, KIND_ABILITY)
			BUFF_ATK:
				buff(sim, target, "atk", value)
			BUFF_HP:
				buff(sim, target, "hp", value)
			_:
				push_error("Unbekannter Effekt: %s" % effect)


static func add_poison(sim: CombatSim, target: CombatUnit, amount: int) -> void:
	if not target.alive or amount <= 0:
		return
	target.poison += amount
	sim.emit({"ev": "poison", "side": target.side, "slot": target.slot, "amount": amount, "total": target.poison})


## Erhöht Angriff oder HP für den Rest des Kampfes. HP-Bonus hebt auch das Maximum.
static func buff(sim: CombatSim, target: CombatUnit, stat: String, amount: int) -> void:
	if not target.alive or amount <= 0:
		return
	if stat == "atk":
		target.atk += amount
	else:
		target.hp += amount
		target.max_hp += amount
	sim.emit({"ev": "buff", "side": target.side, "slot": target.slot, "stat": stat, "amount": amount, "atk": target.atk, "hp": target.hp})


static func add_shield(sim: CombatSim, target: CombatUnit, amount: int) -> void:
	if not target.alive or amount <= 0:
		return
	target.shield += amount
	sim.emit({"ev": "shield", "side": target.side, "slot": target.slot, "amount": amount, "total": target.shield})


## Schild fängt Schaden zuerst ab. Gift geht je nach Regel in balance.json am Schild vorbei.
static func deal_damage(sim: CombatSim, source: CombatUnit, target: CombatUnit, amount: int, kind: String) -> void:
	if not target.alive or amount <= 0:
		return
	var blocked := 0
	var bypass: bool = kind == KIND_POISON and sim.rules.get("poison_ignores_shield", true)
	if not bypass:
		blocked = mini(target.shield, amount)
		target.shield -= blocked
	var dealt := amount - blocked
	target.hp -= dealt
	sim.emit({
		"ev": "damage", "side": target.side, "slot": target.slot, "kind": kind,
		"amount": dealt, "blocked": blocked, "hp": target.hp, "shield": target.shield, "poison": target.poison,
	})
	if target.hp <= 0:
		sim.kill(target)
	elif kind == KIND_ATTACK and dealt + blocked > 0:
		sim.queue_trigger(target, "on_hurt", {"attacker": source})
