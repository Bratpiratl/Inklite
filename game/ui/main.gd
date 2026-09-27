extends Control
## M0: Platzhalter-Hauptszene. Zählt Tipps auf "Start", damit am Handy sichtbar ist, dass Eingaben ankommen.

@onready var _counter_label: Label = %CounterLabel

var _taps := 0


func _ready() -> void:
	%StartButton.pressed.connect(_on_start_pressed)
	_update_label()


func _on_start_pressed() -> void:
	_taps += 1
	_update_label()


func _update_label() -> void:
	_counter_label.text = "Tipps: %d" % _taps
