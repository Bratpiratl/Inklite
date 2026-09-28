class_name Hud
extends HBoxContainer
## Kopfzeile mit Leben, Siegen, Gold und Runde. Jeder Eintrag lässt sich antippen und erklärt sich.

signal info_requested(topic: String)

const TOPICS := {"LivesLabel": "LIVES", "WinsLabel": "WINS", "GoldLabel": "GOLD", "RoundLabel": "ROUND"}


func _ready() -> void:
	for node_name: String in TOPICS:
		var button: Button = get_node("%" + node_name)
		button.pressed.connect(info_requested.emit.bind(TOPICS[node_name]))


func show_run(run: RunState, show_gold: bool = true) -> void:
	%LivesLabel.text = Loc.t("HUD_LIVES", {"n": run.lives})
	%WinsLabel.text = Loc.t("HUD_WINS", {"n": run.wins, "max": run.wins_to_victory()})
	%GoldLabel.text = Loc.t("HUD_GOLD", {"n": run.gold})
	%GoldLabel.visible = show_gold
	%RoundLabel.text = Loc.t("HUD_ROUND", {"n": run.round_number})
