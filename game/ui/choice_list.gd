class_name ChoiceList
extends VBoxContainer
## Liste großer Auswahl-Buttons mit Bild, Name und Beschreibung (Trainer, Trinkets).

signal chosen(id: String)

const BUTTON_HEIGHT := 72
const ICON_SIZE := 48


func show_choices(ids: Array) -> void:
	for child in get_children():
		child.queue_free()
	for id: String in ids:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.icon = Session.item_texture(id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", ICON_SIZE)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 16)
		button.text = "%s\n%s" % [Loc.item(id), AbilityText.describe(Session.item_def(id).get("ability"), true)]
		button.pressed.connect(chosen.emit.bind(id))
		add_child(button)
