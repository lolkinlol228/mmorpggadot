extends Node2D
## Снаряд для картинки: летит от from к to и исчезает. Урон уже посчитан хостом,
## это только видимый след (стрела, огненный шар, луч света, магическая искра).

const SPEED := 520.0
const LOOKS := {   # цвет ядра, цвет следа, толщина
	"arrow": [Color(0.95, 0.9, 0.75), Color(0.75, 0.6, 0.4, 0.5), 1.0],
	"fire": [Color(1.0, 0.85, 0.4), Color(1.0, 0.35, 0.1, 0.7), 3.0],
	"holy": [Color(1.0, 1.0, 0.8), Color(1.0, 0.85, 0.35, 0.6), 2.0],
	"arcane": [Color(0.85, 0.75, 1.0), Color(0.55, 0.35, 1.0, 0.6), 2.0],
}

var from := Vector2.ZERO
var to := Vector2.ZERO
var kind := "arcane"
var boom := 0.0          # радиус вспышки в конце (огненный шар)
var t := 0.0
var dur := 0.2
var game


func _ready() -> void:
	z_index = 40
	dur = maxf(0.08, from.distance_to(to) / SPEED)


func _process(delta: float) -> void:
	t += delta
	if t >= dur + 0.25:
		queue_free()
		return
	if t >= dur and boom > 0.0 and game and game.fx:
		game.fx.burst(to + Vector2(0, -10), LOOKS[kind][1], 14, false)
		boom = 0.0
	queue_redraw()


func _draw() -> void:
	var lk: Array = LOOKS.get(kind, LOOKS.arcane)
	var k := clampf(t / dur, 0.0, 1.0)
	var lift := Vector2(0, -12)                         # снаряд летит на уровне рук, а не по земле
	var head := from.lerp(to, k) + lift
	var tail := from.lerp(to, maxf(0.0, k - (0.35 if kind == "arrow" else 0.25))) + lift
	if t < dur:
		draw_line(tail, head, lk[1], lk[2] + 1.0)
		if kind == "arrow":
			draw_line(head - (to - from).normalized() * 6.0, head, lk[0], 1.0)
		else:
			draw_circle(head, lk[2], lk[0])
	else:
		var fade := 1.0 - (t - dur) / 0.25
		draw_circle(to + lift, (lk[2] + 2.0) * (1.0 + (1.0 - fade) * 2.0), Color(lk[1], lk[1].a * fade))
