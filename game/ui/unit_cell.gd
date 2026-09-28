class_name UnitCell
extends Control
## Ein Feld des 3x3-Rasters: Boden, Monster-Sprite und Werte. Nur Darstellung, keine Spiellogik.
## Im Shop lassen sich Monster antippen und auf andere Felder oder eine DropZone ziehen.

signal tapped(slot: int)
signal dropped_on(from_slot: int, to_slot: int)

const DRAG_KIND := "board_unit"
const SPRITE_ROOT := "res://assets/sprites/"
const LUNGE_DISTANCE := 16.0
const KNOCK_DISTANCE := 5.0
const HP_LAG_DELAY := 0.15
const HP_HIGH := Color(0.45, 0.85, 0.35)
const HP_MID := Color(0.95, 0.8, 0.3)
const HP_LOW := Color(0.95, 0.35, 0.3)
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
@onready var _hp_bar: Control = %HpBar
@onready var _hp_fill: ColorRect = %HpFill
@onready var _hp_lag: ColorRect = %HpLag

var slot := -1
var hp := 0
var shield := 0
var poison := 0
var max_hp := 1
## HP-Balken nur im Kampf, im Shop reichen die Zahlen.
var show_hp_bar := false

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
	_body.scale = Vector2.ONE
	_body.rotation = 0.0
	_body.visible = true
	_sprite.texture = load(SPRITE_ROOT + sprite_path)
	_sprite.flip_h = flip
	_atk_label.text = str(atk)
	_level_label.text = "St.%d" % level
	_level_label.visible = level > 1
	max_hp = maxi(start_hp, 1)
	_hp_bar.visible = show_hp_bar
	set_stats(start_hp, 0, 0)
	_hp_lag.size.x = _hp_fill.size.x


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
	_update_hp_bar()


func set_atk(atk: int) -> void:
	_atk_label.text = str(atk)


## Balken sofort auf den neuen Stand, der helle Rest läuft kurz hinterher.
func _update_hp_bar() -> void:
	max_hp = maxi(max_hp, hp)
	var ratio := clampf(float(hp) / max_hp, 0.0, 1.0)
	var width := roundf(_hp_bar.size.x * ratio)
	_hp_fill.size.x = width
	_hp_fill.color = HP_HIGH if ratio > 0.5 else (HP_MID if ratio > 0.25 else HP_LOW)
	if _hp_lag.size.x < width:
		_hp_lag.size.x = width
	else:
		var tween := _new_tween()
		tween.tween_interval(HP_LAG_DELAY)
		tween.tween_property(_hp_lag, "size:x", width, 0.25)


## Mittelpunkt des Feldes in globalen Koordinaten.
func center() -> Vector2:
	return global_position + size / 2.0


## Vorstoß Richtung Ziel und zurück. Der Aufprall liegt in der Mitte der Dauer.
func lunge(target_center: Vector2, duration: float) -> void:
	var offset := (target_center - center()).normalized() * LUNGE_DISTANCE
	var tween := _new_tween()
	tween.tween_property(_body, "position", offset.round(), duration * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_body, "position", Vector2.ZERO, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Kurz wegstoßen, weg vom Angreifer.
func knock(from: Vector2, duration: float) -> void:
	var dir := (center() - from).normalized()
	var tween := _new_tween()
	tween.tween_property(_body, "position", (dir * KNOCK_DISTANCE).round(), duration * 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(_body, "position", Vector2.ZERO, duration * 0.7).set_ease(Tween.EASE_IN_OUT)


## Aufploppen zu Kampfbeginn.
func pop_in(delay: float, duration: float) -> void:
	_body.pivot_offset = _body.size / 2.0
	_body.scale = Vector2.ZERO
	var tween := _new_tween()
	tween.tween_interval(delay)
	tween.tween_property(_body, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func flash(color: Color, duration: float) -> void:
	var tween := _new_tween()
	_sprite.modulate = color
	tween.tween_property(_sprite, "modulate", Color.WHITE, duration)


## Aufblitzen, schrumpfen, wegkippen, ausblenden.
func die(duration: float) -> void:
	_body.pivot_offset = _body.size / 2.0
	_sprite.modulate = Color(3, 3, 3)
	var tween := _new_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, duration * 0.3)
	tween.tween_property(_body, "scale", Vector2.ONE * 0.4, duration * 0.7).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_body, "rotation", deg_to_rad(-25), duration * 0.7)
	tween.parallel().tween_property(_body, "modulate:a", DEAD_ALPHA, duration * 0.7)
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
