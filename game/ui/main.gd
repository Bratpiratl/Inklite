extends Control
## Titelbildschirm. Start öffnet vorerst den Demo-Kampf (M2).

const BATTLE_SCENE := "res://ui/battle_view.tscn"


func _ready() -> void:
	# Deferred, damit der Button seine Eingabe fertig verarbeitet, bevor die Szene verschwindet.
	%StartButton.pressed.connect(func() -> void: get_tree().change_scene_to_file.call_deferred(BATTLE_SCENE))
