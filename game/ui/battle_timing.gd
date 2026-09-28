class_name BattleTiming
extends RefCounted
## Abspieldauern der Kampfansicht in Sekunden bei 1x. Die Simulation schätzt damit die Kampfdauer,
## damit der Bericht die Kennzahl "Kampfdauer" in Sekunden ausweisen kann.

const T_START := 0.6
const T_TICK := 0.25
const T_ATTACK := 0.2
const T_HIT := 0.06
const T_EFFECT := 0.14
const T_ABILITY := 0.06
const T_ITEM := 0.3
const T_DEATH := 0.2
const T_FLOAT := 0.7

## Wartezeit nach einem Ereignis, genau so wie battle_view.gd sie abspielt.
static func wait_after(event: Dictionary) -> float:
	match event["ev"]:
		"start":
			return T_START
		"tick":
			return T_TICK
		"attack":
			return T_ATTACK * 0.5
		"damage":
			return T_HIT
		"poison", "shield", "buff":
			return T_EFFECT
		"ability":
			return T_ITEM if event.get("source", "") != "" else T_ABILITY
		"death":
			return T_DEATH
	return 0.0


static func duration(events: Array) -> float:
	var total := 0.0
	for event: Dictionary in events:
		total += wait_after(event)
	return total
