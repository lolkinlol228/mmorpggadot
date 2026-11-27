extends Node2D
## Земля карты (готовая картинка из tools/art/world.py) и названия зон на земле.

const Sites := preload("res://scripts/adventure_sites.gd")
const ROCK := preload("res://assets/custom/props/rock.png")
const GROUND := preload("res://assets/custom/world/ground.png")


func _ready() -> void:
	z_index = -10
	for l in World.zones.get("labels", []):
		var lab := Label.new()
		lab.z_index = 45                   # названия мест не прячутся за домами
		lab.z_as_relative = false
		lab.text = l[0]
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.size = Vector2(200, 14)
		lab.position = Vector2(l[1] - 100, l[2] - 7)
		lab.add_theme_font_size_override("font_size", 18)
		lab.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7, 0.55))
		lab.add_theme_constant_override("outline_size", 4)
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		add_child(lab)


func _draw() -> void:
	draw_texture(GROUND, Vector2.ZERO)
	draw_rect(Sites.MINE, Color("#18252c"))
	draw_rect(Sites.MINE.grow(-8), Color("#3e5257"), false, 4.0)
	for wall: Rect2 in Sites.MINE_WALLS:
		draw_rect(wall, Color("#0e171b"))
		draw_rect(wall, Color("#48606a"), false, 2.0)
	for i in 54:
		var point := Sites.MINE.position + Vector2(12 + (i * 137) % 862, 12 + (i * 89) % 658)
		draw_texture_rect(ROCK, Rect2(point, Vector2(19, 13)), false, Color("#647478"))
