extends Control
## Titelbildschirm: neuen Run starten oder gespeicherten fortsetzen.


func _ready() -> void:
	var continue_button: Button = %ContinueButton
	continue_button.visible = Session.has_save()
	continue_button.pressed.connect(_on_continue)
	%StartButton.pressed.connect(_on_new_run)


func _on_new_run() -> void:
	Session.new_run()
	Session.goto(Session.SHOP_SCENE)


func _on_continue() -> void:
	if Session.load_run():
		Session.goto(Session.SHOP_SCENE)
	else:
		Session.clear_save()
		%ContinueButton.visible = false
