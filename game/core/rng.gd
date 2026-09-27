class_name GameRng
extends RefCounted
## Einziger Zufallsgeber der Spiellogik. Liefert nur Ganzzahlen, damit ein Kampf mit gleichem
## Seed auf jeder Plattform (Handy, Server, headless) exakt gleich abläuft.

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


## Ganzzahl im Bereich [0, n).
func next_int(n: int) -> int:
	assert(n > 0, "next_int braucht n > 0")
	return int(_rng.randi() % n)


## Ganzzahl im Bereich [from, to], beide Grenzen eingeschlossen.
func range_int(from: int, to: int) -> int:
	return from + next_int(to - from + 1)


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[next_int(items.size())]


## Fisher-Yates, verändert die übergebene Liste.
func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := next_int(i + 1)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
