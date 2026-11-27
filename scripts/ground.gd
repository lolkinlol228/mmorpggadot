extends Node2D
## Земля карты (готовая картинка из tools/art/world.py) и названия зон на земле.

const Sites := preload("res://scripts/adventure_sites.gd")
const MINE_FLOOR := preload("res://assets/custom/world/mine_floor.png")   # tools/art/mine.py
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


	for l in World.mine_lights:                       # фонари шахты: тёплое пятно поверх всего
		var g := Node2D.new()
		g.position = Vector2(l[0], l[1] + 3)
		g.z_index = 5
		g.z_as_relative = false
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		g.material = mat
		g.set_script(load("res://scripts/glow.gd"))
		g.set("radius", float(l[2]) * 0.5)
		g.set("flicker", true)
		add_child(g)


func _draw() -> void:
	draw_texture(GROUND, Vector2.ZERO)
	draw_texture(MINE_FLOOR, Sites.MINE.position)
