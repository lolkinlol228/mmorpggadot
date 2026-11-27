extends Control
## Кукла персонажа в сумке: тот же собранный спрайт, что и в мире, ×2, плюс оружие.

const CharBaker := preload("res://scripts/char_baker.gd")

var look := {}
var equip := {}:
	set(v):
		equip = v
		sheet = CharBaker.bake(equip, look)
var sheet: Texture2D
var t := 0.0
var row := 0                       # 0 — лицом, 1 — спиной, 2 — боком


func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sheet == null:
		sheet = CharBaker.bake(equip, look)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var frame := int(t * 2.0) % 2
	draw_set_transform(Vector2(32, 60), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 14, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_texture_rect_region(sheet, Rect2(Vector2(-16, -16), Vector2(96, 96)), Rect2(frame * 48, row * 48, 48, 48))
