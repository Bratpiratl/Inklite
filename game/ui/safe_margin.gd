class_name SafeMargin
extends MarginContainer
## MarginContainer, der zu seinen eigenen Rändern die Safe Area addiert (Notch, Gestenleiste).

var _base := Vector4.ZERO


func _ready() -> void:
	_base = Vector4(
		get_theme_constant("margin_left"), get_theme_constant("margin_top"),
		get_theme_constant("margin_right"), get_theme_constant("margin_bottom"))
	get_viewport().size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var inset := SafeArea.insets(get_viewport())
	add_theme_constant_override("margin_left", int(_base.x + inset.x))
	add_theme_constant_override("margin_top", int(_base.y + inset.y))
	add_theme_constant_override("margin_right", int(_base.z + inset.z))
	add_theme_constant_override("margin_bottom", int(_base.w + inset.w))
