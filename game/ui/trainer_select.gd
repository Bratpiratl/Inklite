extends Control
## Trainerwahl zu Beginn eines Runs.


func _ready() -> void:
	var list: ChoiceList = %Choices
	list.chosen.connect(_on_chosen)
	list.show_choices(Session.items.trainer_ids())


func _on_chosen(trainer_id: String) -> void:
	Session.new_run(trainer_id)
	Session.goto(Session.SHOP_SCENE)
