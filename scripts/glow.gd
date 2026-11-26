extends Node2D
## Пятно тёплого света ступеньками (пиксельный стиль), аддитивное.

var radius := 26.0
var flicker := false
var t := 0.0


func _ready() -> void:
	t = randf() * 10.0


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var k := 1.0 + (sin(t * 9.0) * 0.06 + sin(t * 13.0) * 0.04 if flicker else sin(t * 2.0) * 0.03)
	var c := Color(1.0, 0.62, 0.25)
	var boost := 1.0 + World.night * 1.6          # ночью фонари светят заметно ярче
	var size := radius * (1.0 + World.night * 0.3)
	for i in 4:
		draw_circle(Vector2.ZERO, size * k * (1.0 - i * 0.22), Color(c, (0.05 + i * 0.03) * boost))
