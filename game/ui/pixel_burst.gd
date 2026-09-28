class_name PixelBurst
extends Node2D
## Kleines Partikelsystem aus Pixelquadraten, gezeichnet mit draw_rect. Ersetzt CPUParticles2D,
## das im Web-Renderer später ausgestoßene Teilchen schwarz färbt.
## Teilchen schrumpfen am Ende ihrer Lebenszeit, statt auszublenden.

const SHRINK_FROM := 0.7  # ab diesem Anteil der Lebenszeit schrumpft ein Teilchen

var speed := 1.0
var gravity := Vector2.ZERO

var _pos: PackedVector2Array = []
var _vel: PackedVector2Array = []
var _age: PackedFloat32Array = []
var _life: PackedFloat32Array = []
var _size: PackedFloat32Array = []
var _color := Color.WHITE


## origin: Mitte, extents: halbe Ausdehnung des Ausstoßbereichs. delay_spread verteilt den Start
## der Teilchen über diese Zeit (0 = alle sofort). rng sorgt für gleiche Bilder beim Wiederholen.
func setup(rng: GameRng, color: Color, amount: int, origin: Vector2, extents: Vector2, direction: Vector2,
		spread_deg: float, speed_min: float, speed_max: float, lifetime: float, pixel: float, delay_spread: float = 0.0) -> void:
	_color = color
	position = origin
	for i in amount:
		var angle := direction.angle() + deg_to_rad(_range(rng, -spread_deg, spread_deg))
		_pos.append(Vector2(_range(rng, -extents.x, extents.x), _range(rng, -extents.y, extents.y)))
		_vel.append(Vector2.from_angle(angle) * _range(rng, speed_min, speed_max))
		_age.append(-_range(rng, 0.0, delay_spread))
		_life.append(lifetime * _range(rng, 0.8, 1.0))
		_size.append(pixel)


func _process(delta: float) -> void:
	var step := delta * speed
	var alive := false
	for i in _pos.size():
		_age[i] += step
		if _age[i] < 0.0:
			alive = true
			continue
		if _age[i] >= _life[i]:
			continue
		alive = true
		_vel[i] += gravity * step
		_pos[i] += _vel[i] * step
	queue_redraw()
	if not alive:
		queue_free()


func _draw() -> void:
	for i in _pos.size():
		if _age[i] < 0.0 or _age[i] >= _life[i]:
			continue
		var t := _age[i] / _life[i]
		var s := _size[i]
		if t > SHRINK_FROM:
			s = maxf(1.0, roundf(s * (1.0 - (t - SHRINK_FROM) / (1.0 - SHRINK_FROM))))
		draw_rect(Rect2(_pos[i].round() - Vector2(s, s) / 2.0, Vector2(s, s)), _color)


static func _range(rng: GameRng, from: float, to: float) -> float:
	return from + (to - from) * rng.next_int(10001) / 10000.0
