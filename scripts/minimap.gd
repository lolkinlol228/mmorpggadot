extends Control
## Мини-карта: уменьшенная земля, город, игроки (свой — золотой), враги (красные), босс.

const GROUND := preload("res://assets/custom/world/ground.png")
const Kit := preload("res://scripts/ui_kit.gd")

var game
var acc := 0.0
var _frame: StyleBox


func _ready() -> void:
	custom_minimum_size = Vector2(132, 90)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = Kit.box("panel", 0)


func _process(delta: float) -> void:
	acc += delta
	if acc > 0.1:
		acc = 0.0
		queue_redraw()


func _to_map(p: Vector2, inner: Rect2) -> Vector2:
	return inner.position + p / World.size * inner.size


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_frame, r)
	var inner := r.grow(-5)
	draw_texture_rect(GROUND, inner, false, Color(0.85, 0.85, 0.9))
	var town := World.town
	draw_rect(Rect2(_to_map(town.position, inner), town.size / World.size * inner.size), Color(0.95, 0.78, 0.42, 0.8), false, 1.0)
	if game == null:
		return
	for ev in game.enemy_views.values():
		var p := _to_map(ev.position, inner)
		if ev.kind == "golem":
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), Color(1, 0.3, 0.2))
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), Color.BLACK, false, 1.0)
		else:
			draw_rect(Rect2(p, Vector2(1, 1)), Color(0.95, 0.3, 0.3))
	for pid in game.player_views:
		if pid == game.my_id:
			continue
		draw_rect(Rect2(_to_map(game.player_views[pid].position, inner) - Vector2.ONE, Vector2(3, 3)), Color(0.4, 0.75, 1.0))
	var me := _to_map(game.my_pos, inner)
	draw_rect(Rect2(me - Vector2(2, 2), Vector2(5, 5)), Color.BLACK)
	draw_rect(Rect2(me - Vector2(1, 1), Vector2(3, 3)), Color(1, 0.85, 0.3))
