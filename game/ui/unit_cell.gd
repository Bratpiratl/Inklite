class_name UnitCell
extends Control
## Ein Feld des 3x3-Rasters: Boden, Monster-Sprite und Werte. Nur Darstellung, keine Spiellogik.

const SPRITE_ROOT := "res://assets/sprites/"
const JUMP_HEIGHT := 10.0
const DEAD_ALPHA := 0.0
const EMPTY_FLOOR := Color(0.55, 0.55, 0.6)

@onready var _floor: TextureRect = $Floor
@onready var _body: Control = $Body
@onready var _sprite: TextureRect = $Body/Sprite
@onready var _atk_label: Label = %AtkLabel
@onready var _hp_label: Label = %HpLabel
@onready var _shield_label: Label = %ShieldLabel
@onready var _poison_label: Label = %PoisonLabel

var hp := 0
var shield := 0
var poison := 0

var _tweens: Array[Tween] = []


func set_floor(texture: Texture2D) -> void:
	_floor.texture = texture


func show_unit(sprite_path: String, start_hp: int, atk: int, flip: bool) -> void:
	_stop_tweens()
	_floor.modulate = Color.WHITE
	_body.position = Vector2.ZERO
	_body.modulate = Color.WHITE
	_body.visible = true
	_sprite.texture = load(SPRITE_ROOT + sprite_path)
	_sprite.flip_h = flip
	_atk_label.text = str(atk)
	set_stats(start_hp, 0, 0)


func clear() -> void:
	_stop_tweens()
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
