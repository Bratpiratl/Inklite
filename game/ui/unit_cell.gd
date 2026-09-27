class_name UnitCell
extends Control
## Ein Feld des 3x3-Rasters: Boden, Monster-Sprite und Werte. Nur Darstellung, keine Spiellogik.
## Im Shop lassen sich Monster antippen und auf andere Felder oder eine DropZone ziehen.

signal tapped(slot: int)
signal dropped_on(from_slot: int, to_slot: int)

const DRAG_KIND := "board_unit"
const SPRITE_ROOT := "res://assets/sprites/"
const JUMP_HEIGHT := 10.0
const DEAD_ALPHA := 0.0
const DRAG_SOURCE_ALPHA := 0.35
const EMPTY_FLOOR := Color(0.55, 0.55, 0.6)

@onready var _floor: TextureRect = $Floor
@onready var _body: Control = $Body
@onready var _sprite: TextureRect = $Body/Sprite
@onready var _atk_label: Label = %AtkLabel
@onready var _hp_label: Label = %HpLabel
@onready var _shield_label: Label = %ShieldLabel
@onready var _poison_label: Label = %PoisonLabel
@onready var _level_label: Label = %LevelLabel

var slot := -1
var hp := 0
var shield := 0
var poison := 0

var _interactive := false
var _has_unit := false
var _tweens: Array[Tween] = []


func set_floor(texture: Texture2D) -> void:
	_floor.texture = texture


func set_interactive(value: bool) -> void:
	_interactive = value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE


func show_unit(sprite_path: String, start_hp: int, atk: int, level: int, flip: bool) -> void:
	_stop_tweens()
	_has_unit = true
	_floor.modulate = Color.WHITE
	_body.position = Vector2.ZERO
	_body.modulate = Color.WHITE
	_body.visible = true
	_sprite.texture = load(SPRITE_ROOT + sprite_path)
	_sprite.flip_h = flip
	_atk_label.text = str(atk)
	_level_label.text = "St.%d" % level
	_level_label.visible = level > 1
	set_stats(start_hp, 0, 0)


func clear() -> void:
	_stop_tweens()
	_has_unit = false
	_floor.modulate = EMPTY_FLOOR
	_body.visible = false


func set_stats(new_hp: int, new_shield: int, new_poison: int) -> void:
	hp = new_hp
	shield = new_shield
	poison = new_poison
	_hp_label.text = str(maxi(hp, 0))
	_shield_label.text = str(shield)
	_shield_label.visible = shield > 0
	_poison_label.text = str(poison)
	_poison_label.visible = poison > 0


## Kurzer Sprung Richtung Gegner. direction: -1 nach oben, 1 nach unten.
func jump(direction: float, duration: float) -> void:
	var tween := _new_tween()
	tween.tween_property(_body, "position:y", direction * JUMP_HEIGHT, duration * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_body, "position:y", 0.0, duration * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func flash(color: Color, duration: float) -> void:
	var tween := _new_tween()
	_sprite.modulate = color
	tween.tween_property(_sprite, "modulate", Color.WHITE, duration)


func die(duration: float) -> void:
	var tween := _new_tween()
	tween.tween_property(_body, "modulate:a", DEAD_ALPHA, duration)
	tween.tween_callback(clear)


# --- Eingabe (nur im Shop) ---

func _gui_input(event: InputEvent) -> void:
	if not _interactive or not _has_unit:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		tapped.emit(slot)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not _interactive or not _has_unit:
		return null
	var preview := Control.new()
	var image := TextureRect.new()
	image.texture = _sprite.texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.size = _sprite.size
	image.position = -_sprite.size / 2.0
	preview.add_child(image)
	set_drag_preview(preview)
	_body.modulate.a = DRAG_SOURCE_ALPHA
	return {"kind": DRAG_KIND, "slot": slot}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return _interactive and data is Dictionary and data.get("kind", "") == DRAG_KIND


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped_on.emit(int(data["slot"]), slot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _has_unit:
		_body.modulate.a = 1.0


func _new_tween() -> Tween:
	var tween := create_tween()
	_tweens.append(tween)
	tween.finished.connect(func() -> void: _tweens.erase(tween))
	return tween


func _stop_tweens() -> void:
	for tween in _tweens:
		tween.kill()
	_tweens.clear()
	_sprite.modulate = Color.WHITE
