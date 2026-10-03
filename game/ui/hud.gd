class_name Hud
extends SafeMargin
## Kopfleiste über die ganze Breite: Leben, Runde, Siege, Hilfe und Menü. Die Einträge lassen sich
## antippen und erklären sich. Gestreiftes Blau bis unter die Statusleiste.

signal info_requested(topic: String)
signal help_pressed
signal menu_pressed

const TOPICS := {"LivesLabel": "LIVES", "WinsLabel": "WINS", "RoundLabel": "ROUND"}
const FILL := Color(0.25098, 0.737255, 0.952941)
const STRIPE := Color(0.192157, 0.666667, 0.905882)
const RIM := Color(0.137255, 0.509804, 0.776471)
const OUTLINE := Color(0.121569, 0.105882, 0.164706)
const STRIPE_STEP := 6.0


func _ready() -> void:
	super._ready()
	for node_name: String in TOPICS:
		var button: Button = get_node("%" + node_name)
		button.pressed.connect(info_requested.emit.bind(TOPICS[node_name]))
	%HelpButton.pressed.connect(help_pressed.emit)
	%MenuButton.pressed.connect(menu_pressed.emit)
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FILL)
	var y := 2.0
	while y < size.y - 5.0:
		draw_rect(Rect2(0, y, size.x, 2), STRIPE)
		y += STRIPE_STEP
	draw_rect(Rect2(0, size.y - 5, size.x, 2), RIM)
	draw_rect(Rect2(0, size.y - 3, size.x, 3), OUTLINE)


## show_gold bleibt für Aufrufer erhalten, Gold steht im Shop neben den Angeboten.
func show_run(run: RunState, _show_gold: bool = true) -> void:
	%LivesLabel.text = str(run.lives)
	%WinsLabel.text = "%d/%d" % [run.wins, run.wins_to_victory()]
	%RoundLabel.text = Loc.t("HUD_ROUND", {"n": run.round_number}).to_upper()
