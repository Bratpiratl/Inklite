extends CanvasLayer
## Autoload: Hinweis bei Querformat. Das Spiel sperrt die Drehung nicht, bittet aber ums Hochformat.

@onready var _root: Control = $Root


func _ready() -> void:
	get_viewport().size_changed.connect(_update)
	_update()


func _update() -> void:
	var size := get_viewport().get_visible_rect().size
	_root.visible = size.x > size.y
