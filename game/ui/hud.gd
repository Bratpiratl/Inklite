class_name Hud
extends HBoxContainer
## Kopfzeile mit Leben, Siegen, Gold und Runde.


func show_run(run: RunState, show_gold: bool = true) -> void:
	%LivesLabel.text = "Leben %d" % run.lives
	%WinsLabel.text = "Siege %d/%d" % [run.wins, run.wins_to_victory()]
	%GoldLabel.text = "Gold %d" % run.gold
	%GoldLabel.visible = show_gold
	%RoundLabel.text = "Runde %d" % run.round_number
