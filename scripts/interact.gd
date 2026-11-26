extends Node2D
## Метки над всем, с чем можно взаимодействовать (хранилище, торговка, доска, жители):
## покачивающийся значок, кольцо на земле и подсказка «[E] …», когда подходишь или наводишь мышь.
## Всё без значка — декорация.

const Kit := preload("res://scripts/ui_kit.gd")
const RANGE := 40.0
const ICONS := {"bank": "coin", "shop": Vector2i(0, 10), "board": "!", "talk": Vector2i(1, 4)}

var game
var spots: Array = []
var focused := -1
var prompt: Label
var t := 0.0


func _ready() -> void:
	z_index = 40
	spots = World.zones.get("interact", [])
	prompt = Kit.label("", 9, Color(1, 0.92, 0.6))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.size = Vector2(140, 12)
	prompt.visible = false
	add_child(prompt)


func spot(i: int) -> Dictionary:
	return spots[i]


func _process(delta: float) -> void:
	t += delta
	var best := -1
	var best_d := RANGE
	var mouse := get_global_mouse_position()
	for i in spots.size():
		var p := Vector2(spots[i].x, spots[i].y)
		var d := p.distance_to(game.my_pos)
		var hover := mouse.distance_to(p - Vector2(0, float(spots[i].h) * 0.5)) < 14.0 and d < 140.0
		if hover:
			d = 0.0
		if d < best_d:
			best_d = d
			best = i
	focused = best
	if focused >= 0:
		var s: Dictionary = spots[focused]
		prompt.text = "[E] " + s.label
		prompt.position = Vector2(s.x - 70, s.y - float(s.h) - 26)
		prompt.visible = true
	else:
		prompt.visible = false
	queue_redraw()


func _draw() -> void:
	for i in spots.size():
		var s: Dictionary = spots[i]
		var base := Vector2(s.x, s.y)
		var top := base - Vector2(0, float(s.h) + 8 + sin(t * 3.0 + i) * 2.0)
		var on := i == focused
		if on:                                                    # кольцо на земле под целью
			draw_set_transform(base + Vector2(0, 1), 0, Vector2(1, 0.4))
			draw_arc(Vector2.ZERO, 13.0 + sin(t * 5.0), 0, TAU, 24, Color(1, 0.9, 0.5, 0.8), 1.5)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var a := 1.0 if on else 0.8
		draw_circle(top, 6.5, Color(0.08, 0.07, 0.11, 0.75 * a))
		draw_arc(top, 6.5, 0, TAU, 16, Color(1, 0.85, 0.45, a), 1.0)
		var ic = ICONS[s.kind]
		if ic is Vector2i:
			draw_texture_rect(Items.icon_at(ic), Rect2(top - Vector2(5, 5), Vector2(10, 10)), false, Color(1, 1, 1, a))
		elif ic == "coin":
			draw_texture_rect(Items.coin_icon(1), Rect2(top - Vector2(5, 5), Vector2(10, 10)), false, Color(1, 1, 1, a))
		else:
			draw_rect(Rect2(top + Vector2(-1, -4), Vector2(2, 5)), Color(1, 0.85, 0.3, a))
			draw_rect(Rect2(top + Vector2(-1, 2), Vector2(2, 2)), Color(1, 0.85, 0.3, a))
